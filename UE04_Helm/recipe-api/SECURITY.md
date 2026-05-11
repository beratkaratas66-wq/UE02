# Exercise 4: Helm & Security

## Part A.3: Health Checks
**Why do health checks (Liveness & Readiness Probes) matter for security?**
As shown in the lecture, without health checks, crashed or compromised pods keep receiving network traffic. If an attacker manages to compromise a pod and corrupts its primary process, or if the pod enters a vulnerable state and crashes, a Readiness Probe ensures that Kubernetes immediately stops routing user traffic to this compromised pod. A Liveness Probe ensures the pod is killed and restarted from a clean, secure image state.

---

## Part B.1: Production vs Development Values
Here are the key differences between my `values-dev.yaml` and `values-prod.yaml`:

* **Replica Count:** `dev` uses 1 (saves local resources), `prod` uses 3 (high availability).
* **Image Pull Policy & Tag:** `dev` uses `:latest` and `Always` (to quickly pull new builds). `prod` uses a fixed version tag (e.g., `:v1.0.0`) and `IfNotPresent` for reproducibility and protection against malicious image overrides.
* **Ingress TLS:** `dev` disables Ingress or uses HTTP via NodePort. `prod` enables Ingress and strictly configures TLS to encrypt traffic end-to-end.
* **Resource Limits:** `dev` has no limits to avoid arbitrary throttling during debugging. `prod` strictly defines CPU/Memory limits to prevent DoS attacks and noisy neighbor issues.
* **Security Context:** `dev` runs normally. `prod` is hardened: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, and drops all capabilities to prevent privilege escalation.

---

## Part B.2: Helm Chart Security Audit (`insecure-chart/`)
Based on the provided files in `insecure-chart/`, I found the following vulnerabilities:

1.  **Plaintext Passwords in values.yaml:** * *Issue:* `dbPassword: "SuperSecret123!"` is hardcoded.
    * *Attack:* Anyone with access to the Git repository or the cluster can read the password.
    * *Fix:* Remove default passwords. Use a K8s `Secret` template and `b64enc` in Helm, and inject via `secretKeyRef` in the deployment.
2.  **No Security Context:** * *Issue:* `securityContext` is empty, meaning the container runs as `root` by default.
    * *Attack:* If the container is compromised, the attacker has root privileges and can attempt to break out to the host node.
    * *Fix:* Define `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, and drop capabilities.
3.  **No Resource Limits:** * *Issue:* `resources: {}` is empty.
    * *Attack:* Denial of Service (DoS). An attacker can trigger a memory leak or CPU spike in the pod, consuming all node resources and crashing other applications.
    * *Fix:* Define memory and CPU `requests` and `limits`.
4.  **No Health Probes:** * *Issue:* No liveness or readiness probes in the deployment.
    * *Attack:* Traffic is continuously sent to unresponsive, crashed, or compromised pods.
    * *Fix:* Implement HTTP health checks on the API endpoints.
5.  **No TLS on Ingress:** * *Issue:* `tls: []` is empty.
    * *Attack:* Man-in-the-Middle (MitM) attacks. User credentials and recipes are sent in cleartext over the network.
    * *Fix:* Add TLS configuration and a `secretName` with valid certificates to the Ingress resource.
6.  **Mutable Image Tag:** * *Issue:* `tag: "latest"`.
    * *Attack:* If the image registry is compromised and the `latest` tag is overwritten with malware, the cluster will automatically deploy the infected image upon restart.
    * *Fix:* Pin a specific version (e.g., `tag: "1.2.0"`).

---

## Part B.3: Secrets in GitOps
**Why is it a problem to store K8s Secrets (even base64-encoded) in Git?**
Base64 is an encoding method, NOT encryption. Anyone who can read the Git repository can easily decode the string (e.g., `echo "..." | base64 -d`) and obtain the plaintext password. Git repositories are often accessible to many developers or CI/CD tools, leading to massive credential exposure.

