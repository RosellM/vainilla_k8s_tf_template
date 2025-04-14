# 🚀 Instalación de AWS Load Balancer Controller en Kubernetes Vanilla (EC2)

## ✅ 0. Prerrequisitos
- Clúster Kubernetes Vanilla funcionando (kubeadm + Calico + containerd)
- Red pod-to-pod y pod-to-service OK ✅
- `nginx-deployment` y `nginx-service` (`NodePort`) activos ✅
- Subred pública con etiquetas:
  - `kubernetes.io/role/elb = 1`
  - `kubernetes.io/cluster/my-k8s-cluster = owned`

## 🔐 1. Crear IAM Policy para el ALB Controller
- Descargamos el archivo oficial `iam_policy.json`
- Creamos en IAM la policy: `AWSLoadBalancerControllerPolicy`
- Creamos un nuevo IAM Role para EC2 y lo asociamos con esta policy

## 🧷 2. Asociar IAM Role a los nodos EC2
- Usamos la consola de EC2 → Actions → Security → Modify IAM Role
- Asociamos el role `EC2Role-K8s-ALBController` a todos los nodos

## 📦 3. Instalación del AWS Load Balancer Controller

### A. Aplicamos los CRDs (versión funcional)
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/v2_7_1_full.yaml
```

### B. Corregimos el Deployment:
- Flags:
  - `--region` → `--aws-region`
  - `--vpc-id` → `--aws-vpc-id`
- Removimos: `--enable-webhooks`
- Agregamos:
```yaml
serviceAccountName: aws-load-balancer-controller
```

- Args actualizados:
```yaml
args:
  - --cluster-name=my-k8s-cluster
  - --aws-region=us-east-1
  - --aws-vpc-id=vpc-04ca3b77d83723121
  - --ingress-class=alb
```

## ⚠️ 4. Solucionamos errores de red y Calico

### Problemas encontrados:
- `calico-node` con errores de `bird.cfg` no generado
- `i/o timeout` en el ALB Controller al contactar el API Server

### Acciones tomadas:
- Reprogramamos el ALB Controller (`kubectl delete pod ...`)
- Verificamos nodos con `calico-node` en `1/1 Running`
- Planeamos usar `nodeSelector` si persiste el problema

## 🌐 5. Creación del Ingress
Archivo usado:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: nginx-service
              port:
                number: 80
```

## 🧹 Pendientes
- Limpiar e instalar Calico correctamente (CRDs + Installation)
- Verificar conectividad pod-to-service
- Validar creación automática del ALB (`kubectl get ingress` → columna ADDRESS)

---

> Este resumen fue generado junto a Rossell en su aventura por instalar el AWS Load Balancer Controller desde cero, usando solo EC2, kubeadm y mucha persistencia 💪✨

