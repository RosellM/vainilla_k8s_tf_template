provider "aws" {
  region = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID para las instancias EC2"
  type        = string
}

# ------------------------
# VPC
# ------------------------
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "k8s-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "k8s-igw"
  }
}

# ------------------------
# Subnets
# ------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-public-subnet"
  }
}

resource "aws_subnet" "private_master" {
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "k8s-private-master"
  }
}

resource "aws_subnet" "private_worker1" {
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "k8s-private-worker1"
  }
}

resource "aws_subnet" "private_worker2" {
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "k8s-private-worker2"
  }
}

# ------------------------
# Route Tables
# ------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "k8s-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "k8s-nat-gateway"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "k8s-private-rt"
  }
}

resource "aws_route_table_association" "private_master_assoc" {
  subnet_id      = aws_subnet.private_master.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_worker1_assoc" {
  subnet_id      = aws_subnet.private_worker1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_worker2_assoc" {
  subnet_id      = aws_subnet.private_worker2.id
  route_table_id = aws_route_table.private_rt.id
}

# ------------------------
# Security Groups
# ------------------------
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-sg"
  description = "Allow SSH and Kubernetes traffic"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  ingress {
    description = "K8s API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "K8s node ports"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-sg"
  }
}

resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH from anywhere"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "SSH from internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

# ------------------------
# Bastion Host
# ------------------------

data "template_file" "pem_injector" {
  template = <<-EOF
    #!/bin/bash
    mkdir -p /home/ubuntu/.ssh
    echo "$${pem_content}" > /home/ubuntu/.ssh/k8s_key.pem
    chmod 600 /home/ubuntu/.ssh/k8s_key.pem
    chown ubuntu:ubuntu /home/ubuntu/.ssh/k8s_key.pem
  EOF

  vars = {
    pem_content = file("${path.module}/k8s_key.pem")
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name                    = "k8s_key"
  user_data = data.template_file.pem_injector.rendered
  tags = {
    Name = "k8s-bastion"
  }
}

# ------------------------
# User Data Script (containerd)
# ------------------------
data "template_file" "install_containerd" {
  template = <<-EOF
    #!/bin/bash
    set -e
    
    #Se agrega contanerd, runc y cni
    sudo wget https://github.com/containerd/containerd/releases/download/v2.0.4/containerd-2.0.4-linux-amd64.tar.gz
    sudo tar Cxzvf /usr/local containerd-2.0.4-linux-amd64.tar.gz

    sudo mkdir /usr/local/lib/systemd/
    sudo mkdir /usr/local/lib/systemd/system/
    sudo wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    sudo cp ./containerd.service /usr/local/lib/systemd/system/containerd.service

    sudo systemctl daemon-reload
    sudo systemctl enable --now containerd

    sudo wget https://github.com/opencontainers/runc/releases/download/v1.2.6/runc.amd64
    sudo install -m 755 runc.amd64 /usr/local/sbin/runc


    sudo wget https://github.com/containernetworking/plugins/releases/download/v1.6.2/cni-plugins-linux-amd64-v1.6.2.tgz
    sudo mkdir -p /opt/cni/bin
    tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.6.2.tgz

    sudo apt-get update && apt-get install -y curl wget tar apt-transport-https ca-certificates gpg

    # Kubernetes v1.31
    sudo mkdir -p -m 755 /etc/apt/keyrings
    sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl

    # Ajustes del sistema
    sudo swapoff -a
    sudo sed -i '/ swap / s/^/#/' /etc/fstab
    sudo sysctl -w net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    sudo sysctl -p

    sudo mkdir -p /etc/containerd/
    sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
    sudo systemctl restart containerd
  EOF
}

# ------------------------
# EC2 Instances
# ------------------------
resource "aws_instance" "k8s_master" {
  ami                         = var.ami_id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.private_master.id
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = false
  key_name                    = "k8s_key"
  user_data                   = data.template_file.install_containerd.rendered

  tags = {
    Name = "k8s-master"
  }
}

resource "aws_instance" "k8s_worker1" {
  ami                         = var.ami_id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.private_worker1.id
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = false
  key_name                    = "k8s_key"
  user_data                   = data.template_file.install_containerd.rendered

  tags = {
    Name = "k8s-worker-1"
  }
}
