# UE02## Exercise 2: Supply Chain Security Analysis

### 1. Dependency Trust Audit

**Übersicht der verwendeten Third-Party Actions:**
* `actions/checkout` & `actions/setup-go`: Maintained von GitHub (Verified).
* `hadolint/hadolint-action`: Maintained von der Hadolint-Community.
* `golangci/golangci-lint-action`: Maintained vom offiziellen golangci-lint Team.
* `docker/*-action`: Maintained von Docker Inc. (Verified).
* `aquasecurity/trivy-action`: Maintained von Aqua Security (Verified).

**Risiko von Tag-basiertem Pinning:**
Das Pinnen auf einen mutablen Tag wie `@v3` (oder `@latest`) birgt ein hohes Supply-Chain-Risiko. Ein Angreifer, der den Account eines Maintainers kompromittiert, könnte bösartigen Code unter dem gleichen Tag pushen (ähnlich dem Vorfall bei `tj-actions/changed-files`). Jeder CI-Lauf würde dann unbemerkt die kompromittierte Version ziehen und den Code ausführen.

**Umsetzung (SHA-Pinning):**
Um dieses Risiko zu mitigieren, wurden alle Actions in unserer Pipeline auf unveränderliche Commit-SHAs gepinnt (z.B. `actions/checkout@eef61447...`). Ein Hash ist kryptografisch an den exakten Code-Zustand gebunden. Wenn das Action-Repository manipuliert wird, ändert sich der Hash, und unsere Pipeline würde den neuen (möglicherweise böswilligen) Code nicht ausführen.

### 2. Secrets Management

**Benötigte Secrets:**
* `${{ secrets.GITHUB_TOKEN }}`: Wird dynamisch bereitgestellt und benötigt die Berechtigung `packages: write`, um Images in die GitHub Container Registry (GHCR) zu pushen.

**Blast Radius bei einem Leak von DOCKER_TOKEN:**
Sollte ein Token mit Push-Rechten für die Container-Registry geleakt werden, könnte ein Angreifer:
1. Das offizielle Image überschreiben (Denial of Service).
2. Eine mit Malware versehene Version der Recipe API veröffentlichen (Supply Chain Attack auf Endnutzer).
*Eindämmung:* Verwendung von kurzlebigen Tokens, Einschränkung der Scopes (nur Push, kein Delete), und IP-Restriktionen für den Registry-Zugriff.

**GITHUB_TOKEN vs. Personal Access Token (PAT):**
Das automatische `GITHUB_TOKEN` ist wesentlich sicherer als ein PAT. Es wird am Anfang eines Jobs erstellt und verfällt sofort nach dessen Abschluss. Ein PAT ist hingegen meist langlebig und oft an die weitreichenden Rechte eines Entwickler-Accounts gebunden, was den potenziellen Schaden bei einem Leak massiv erhöht.

**Erkennung von Exfiltration via PR:**
Ein Angreifer könnte in einem PR ein Skript einbauen, das Umgebungsvariablen sammelt und per `curl` an einen externen Server sendet (Exfiltration). Dies kann entdeckt/verhindert werden durch:
* Code Reviews von Änderungen in `.github/workflows/`.
* Die GitHub-Einstellung "Require approval for all outside collaborators", damit Pipelines bei Forks nicht automatisch anlaufen.
* Egress-Netzwerkfilter auf den CI-Runnern (wenn self-hosted).

### 3. Pipeline Hardening

In der `ci.yml` wurden folgende Hardening-Schritte umgesetzt:

1. **Least-Privilege Permissions Block:** Auf Root-Ebene der Pipeline ist `permissions: contents: read` gesetzt. Nur der Job, der auch tatsächlich das Image pusht (`build-scan-push`), bekommt die erweiterte Berechtigung `packages: write`.
2. **Trivy mit `--exit-code 1`:** Der Scanner reportet Schwachstellen nicht nur, sondern der Parameter `exit-code: '1'` sorgt dafür, dass die Pipeline hart fehlschlägt, falls Schwachstellen mit der Severity HIGH oder CRITICAL in den Go-Bibliotheken oder dem OS-Base-Image (z.B. Alpine/Distroless) gefunden werden.
3. **SBOM Generation:** Der Docker-Build verwendet `sbom: true`. Dadurch wird automatisch eine Software Bill of Materials in das Image eingebettet, die alle verwendeten Go-Module und Systempakete transparent auflistet.
4. **Pinned Runner Image:** Die Jobs verwenden `ubuntu-24.04` statt `ubuntu-latest`, um deterministische Builds zu garantieren und plötzliche Brüche durch OS-Upgrades auf dem Runner zu vermeiden.