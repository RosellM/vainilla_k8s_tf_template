# 🧠 Panorama técnico: Container Runtime en Kubernetes

## 🧭 Flujo general: del Pod al Kernel

```
                 ┌────────────────────────────┐
                 │        kubectl apply       │
                 └────────────┬───────────────┘
                              │
                              ▼
                 ┌────────────────────────────┐
                 │        kubelet (por nodo)  │◄────────────┐
                 └────────────┬───────────────┘             │
                              │                              │
                 ┌────────────▼─────────────┐                │
                 │      containerd          │◄─ SystemdCgroup = true
                 └────────────┬─────────────┘
                              │
                              ▼
                 ┌────────────────────────────┐
                 │          runc              │
                 └────────────┬───────────────┘
                              │
                              ▼
        ┌──────────────────────────────┐
        │     Kernel de Linux (cgroups)│
        │ ┌──────────────────────────┐ │
        │ │ Limita CPU, Memoria, etc│ │
        │ └──────────────────────────┘ │
        └──────────────────────────────┘
```

---

## 🔗 Relación entre componentes

| Componente        | Rol |
|------------------|-----|
| `kubectl`         | Solicita recursos al clúster |
| `kubelet`         | Recibe la orden, coordina y gestiona contenedores |
| `containerd`      | Administra contenedores, volúmenes, red, ejecución |
| `runc`            | Crea y ejecuta el contenedor en el SO |
| `cgroups`         | Kernel aplica límites y aislamiento de recursos |

---

## ⚙️ Configuración clave

| Archivo                         | Uso |
|--------------------------------|-----|
| `/etc/containerd/config.toml`  | Configura containerd: CNI, cgroups, runtime |
| `/opt/cni/bin`                 | Plugins de red usados por containerd |
| `/etc/cni/net.d`               | Archivos de configuración de red (por ejemplo: Calico) |
| `/etc/fstab` + `swapoff`       | Desactivar swap (requisito de Kubernetes) |

---

## 🔌 Flujo de red CNI (ejemplo con Calico)

```
  Pod1 ─────┐
            │
        [ Calico / CNI plugin ]
            │
         bridge interface (cni0)
            │
         eth0 del nodo
            │
       comunicación entre nodos
```

---

## 🔧 ¿Qué es `SystemdCgroup = true`?

Permite que `containerd` y `kubelet` usen el mismo gestor de cgroups (`systemd`), lo cual es **necesario para evitar errores en nodos** y asegurar un manejo coherente de recursos.

---

## 🎓 Analogía

> Kubernetes es el **coreógrafo**,  
> `kubelet` el **coordinador**,  
> `containerd` el **manager**,  
> `runc` el **actor**,  
> y el **kernel con cgroups** es el **equipo técnico** que pone límites de luz, sonido y duración de la función 🎭⚙️
