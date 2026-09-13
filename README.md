## Bloque 1: Orquestación y Balanceo con Docker Swarm (30 min)

### 1. Inicialización y Escalado Horizontal (15 min)
* **Concepto:** Pasar de un contenedor aislado al escalado horizontal en red virtual (*Routing Mesh*).
* **Comandos en Vivo:**
  ```bash
  # Convertir el motor de Docker en un clúster Swarm
  docker swarm init

  # Crear un servicio balanceado con 3 réplicas
  docker service create --name <nombre> --replicas <cantidad> -p <externo>:<interno> <imagen>

  # Escalar dinámicamente
  docker service scale <nombre>=<cantidad>

### 2. Gráfico de Kubernetes
  ┌─────────────────────────────────────────────────────────────────────────┐
│                          KUBERNETES CLUSTER                             │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                        CONTROL PLANE                            │   │
│   │                                                                 │   │
│   │   ┌───────────────┐     ┌───────────────┐     ┌─────────────┐   │   │
│   │   │  API Server   │ ◄─► │     etcd      │     │ Scheduler   │   │   │
│   │   └───────┬───────┘     └───────────────┘     └─────────────┘   │   │
│   │           │                                                     │   │
│   │           ▼                                                     │   │
│   │   ┌───────────────┐                                             │   │
│   │   │ Controller M. │                                             │   │
│   │   └───────────────┘                                             │   │
│   └───────────┬─────────────────────────────────────────────────────┘   │
│               │                                                         │
│               │ (Instrucciones de orquestación)                         │
│               ▼                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                          WORKER NODES                           │   │
│   │                                                                 │   │
│   │   ┌─────────────────────────────────────────────────────────┐   │   │
│   │   │ NODE 1                                                  │   │   │
│   │   │  [ Kubelet ] ──► [ Container Runtime ]                  │   │   │
│   │   │                        │                                │   │   │
│   │   │                        ▼                                │   │   │
│   │   │            ┌───────────────────────┐                    │   │   │
│   │   │            │         POD           │                    │   │   │
│   │   │            │ ┌───────────────────┐ │                    │   │   │
│   │   │            │ │ Contenedor App    │ │                    │   │   │
│   │   │            │ └───────────────────┘ │                    │   │   │
│   │   │            └───────────────────────┘                    │   │   │
│   │   └─────────────────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘

## Instalación Kubernetes local (minikube)
* **Link kubectl:**
  https://kubernetes.io/docs/tasks/tools/
* **Link minikube:**
  https://minikube.sigs.k8s.io/docs/start/?arch=%2Fwindows%2Fx86-64%2Fstable%2F.exe+download
##

## Iniciar minikube:
```bash
minikube start --kubernetes-version=v1.30.0
```
## Correr contenedores con kubernetes:
```bash
kubectl apply -f <archivo de configuracion>
``` 
## Consultar estado del cluster
```bash
kubectl cluster-info
``` 
## Ver despliegues
```bash
kubectl get deployments
``` 
## Ver servicios
```bash
kubectl get services
``` 
## Ver pods
```bash
kubectl get pods
``` 
## Ver servicios en kubernetes
```bash
minikube service list
``` 
## Iniciar servicio
```bash
minikube service <nombre del servicio>
```