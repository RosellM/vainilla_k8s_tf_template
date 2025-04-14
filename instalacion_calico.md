# 🐆 Instalación Completa y Segura de Calico en Kubernetes Vanilla (con containerd)

Este procedimiento cubre la instalación de Calico en un clúcster de Kubernetes creado con `kubeadm`, usando `containerd` como runtime y redes privadas/subredes en EC2.

---

## ✅ Requisitos previos
- Kubernetes inicializado con `kubeadm init --pod-network-cidr=192.168.0.0/16`
- Red entre nodos funcionando
- `containerd` instalado y funcionando
- Todos los nodos tienen conectividad al API Server
- **NO instalar ningún otro CNI antes de Calico**

---

## 🧹 Paso 0: Limpiar instalación anterior (si aplica)
```bash
kubectl delete -f calico-installation.yaml || true
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/tigera-operator.yaml || true
kubectl delete crd installations.operator.tigera.io || true
```

---

## 🧱 Paso 1: Instalar el tigera-operator
> Usamos `kubectl create` para evitar errores de annotations muy largos

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/tigera-operator.yaml
```

Verifica que se crea el namespace `calico-system`:
```bash
kubectl get ns calico-system
```

---

## 📦 Paso 2: Crear el manifiesto de tipo Installation
> Este objeto es lo que hace que el operador instale Calico en los nodos

### Archivo: `calico-installation.yaml`
```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 192.168.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
```

### Aplicar:
```bash
kubectl apply -f calico-installation.yaml
```

---

## 🔍 Paso 3: Verificación

### Ver pods de Calico:
```bash
kubectl get pods -n calico-system -o wide
```
Debes ver:
```
calico-node-xxxxx              1/1     Running
calico-kube-controllers-xxxxx  1/1     Running
calico-typha-xxxxx             1/1     Running
```

### Ver estado de red:
```bash
kubectl run curlbox --image=curlimages/curl -it --rm --restart=Never -- sh
```
Dentro del pod:
```bash
curl http://nginx-service
```
✅ Si responde, hay red pod-to-service

---

## 🛠 Problemas comunes y soluciones

### ❌ `bird.cfg` no se genera:
- Verifica si el pod `calico-node` tiene logs como:
```
bird: Unable to open configuration file /etc/calico/confd/config/bird.cfg
```
✅ Solución:
- Asegúrate de que el API Server esté accesible (`curl -k https://10.96.0.1:443` desde el nodo)
- Reinstala Calico (tigera + installation) con el orden correcto

### ❌ `calico-node` en `0/1 Running`:
- Puede ser por:
  - Faltan módulos del kernel (`ip_tables`, `xt_set`, etc.)
  - CNI no instalado en `/etc/cni/net.d`
  - Nodo no puede alcanzar el API Server

### ✅ Tips
- Usa `kubectl describe pod calico-node-xxxxx -n calico-system` para ver detalles
- Aseg- Aseg\u00rate de que el nodo tiene el hostname resolvible

---

> Documentado junto a Rossell luego de depurar un entorno real de Kubernetes Vanilla en EC2 usando containerd + Calico 🧠💥

