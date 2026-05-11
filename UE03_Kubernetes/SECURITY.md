# Exercise 3: Kubernetes — Attack & Defense

## Part A: Kubernetes Fundamentals

### 1. Cluster Connection
**What is a kubeconfig context and why does it matter for security?**
A context in the kubeconfig is a grouping of a cluster, a user, and a namespace. It determines where commands are sent and with what permissions. Security relevance: Working in the wrong context (e.g., accidentally deploying to "Production" instead of "Staging") could lead to the unintended deletion or manipulation of critical live systems.

**Where is your kubeconfig file stored? What file permissions should it have and why?**
The file is stored by default at `~/.kube/config`. It should have strict file permissions of `600` (read and write access *only* for the owner). Reason: It contains sensitive credentials, client certificates, and tokens. If another user (or a compromised process) on the system can read it, they gain full administrative access to your Kubernetes cluster.

### 2. kubectl Cheat Sheet
* `kubectl get pods -A` : Lists all pods across all namespaces.
* `kubectl get nodes` : Shows all worker nodes and control plane nodes in the cluster.
* `kubectl get svc -A` : Lists all services (network endpoints) across all namespaces.
* `kubectl run test-nginx --image=nginx && kubectl logs test-nginx` : Starts an Nginx pod and outputs its logs to the terminal.
* `kubectl exec -it <pod-name> -- /bin/sh` : Opens an interactive shell inside the running container.
* `kubectl port-forward pod/<pod-name> 8080:80` : Forwards local port 8080 to port 80 of the pod in the cluster.

### 3. Kubernetes Architecture
**What are the most common Kubernetes resource types and when would you use each?**
* **Pod:** The smallest K8s object, containing one or more containers. Rarely created directly.
* **Deployment:** Manages pod replicas, automatic restarts, and rolling updates for stateless applications (e.g., web servers).
* **StatefulSet:** Like a Deployment, but for stateful apps (e.g., databases). Guarantees fixed network names and persistent storage.
* **DaemonSet:** Ensures that exactly one pod runs on *every* worker node (e.g., logging agents).

**What are the different methods to expose a service externally? Compare their security implications:**
* **NodePort:** Opens a static port (30000-32767) on every worker node. Insecure, exposes direct ports to the outside.
* **LoadBalancer:** Uses a cloud provider's load balancer. More secure, but exposes the service directly to the internet on Layer 4.
* **Ingress:** A smart router (Layer 7) that distributes traffic based on URLs. Very secure, allows centralized SSL/TLS termination and firewalls.

**Why should you never use `hostNetwork: true` in production?**
This causes the container to share the network interface directly with the underlying worker node. If the container is hacked, the attacker can sniff all network traffic on the node and access local, internal services on the host server.

---

## Part B: RBAC — Design, Implement, Test

### 2. Test & Prove
Here are the proofs that the RBAC configuration successfully restricts the `pod-reader-sa` ServiceAccount:

* **Prove that I CAN list pods:**
  *Command:* `kubectl get pods`
  *Result:* 
  NAME           READY   STATUS    RESTARTS   AGE 
  kubectl-test   1/1     Running   0          3m11s

* **Prove that I CANNOT create/delete pods:**
  *Command:* `kubectl run hack --image=nginx`
  *Result:* `Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:default:pod-reader-sa" cannot create resource "pods" in API group "" in the namespace "default"`

* **Prove that I CANNOT list pods in other namespaces:**
  *Command:* `kubectl get pods -n kube-system`
  *Result:* `Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:default:pod-reader-sa" cannot list resource "pods" in API group "" in the namespace "kube-system"`

### 3. Escalation Analysis
**What would happen if you gave this service account `create` permission on Pods?**
This leads directly to privilege escalation. An attacker could create a malicious pod that mounts the `hostPath` volume `/` (the entire filesystem of the worker node), sets `privileged: true`, and runs as `root`. This grants them complete control over the K8s host node.

**What is the difference between a Role/RoleBinding and a ClusterRole/ClusterRoleBinding?**
* **Role / RoleBinding:** Apply *only* within a specific namespace. Used to isolate teams.
* **ClusterRole / ClusterRoleBinding:** Apply cluster-wide (across all namespaces). Used for K8s administrators or node agents.

**What is the `system:anonymous` user in Kubernetes?**
This is the default user for all requests to the K8s API that fail to authenticate successfully. This user should have absolutely no permissions, otherwise the cluster would be freely manipulable by any unauthenticated attacker.

---

## Part C: Pod Security

### 2. Security Hardening
**Why are unbounded resources a DoS risk?**
If a pod lacks CPU and memory limits, a memory leak or a DDoS attack could cause the container to consume all the memory or CPU of the K8s worker node (Resource Exhaustion). This crashes all other containers on that node.

**Vulnerability Scan of `insecure-deployment/` (The 6 Vulnerabilities):**
1. **`privileged: true` (deployment.yaml):** Container can do almost everything the host can. Bypasses container security.
2. **`runAsUser: 0` (deployment.yaml):** Container explicitly runs as the root user.
3. **HostPath Volume Mount (deployment.yaml):** Entire filesystem of the K8s host (`path: /`) is mounted into the container. An attacker can manipulate the node OS.
4. **`hostNetwork: true` (db-deployment.yaml):** Database shares the network stack directly with the host server, bypassing K8s network isolation.
5. **Plaintext Passwords (both files):** `DB_PASSWORD` and `POSTGRES_PASSWORD` are written unencrypted directly in the YAML code.
6. **`:latest` Tags (both files):** The images `recipe-api:latest` and `postgres:latest` use mutable tags. An attacker could overwrite the image in the registry, causing K8s to pull malicious code.

