# Voting App — Container Security Verification

**Verification date:** 12 November 2026
**Environment:** Linux Mint, Docker Engine
**Scope:** Vote, Worker, and Results production images

## 1. Security controls

- Pinned production base-image digests
- Non-root application execution
- Production-only dependency installation
- Multi-stage Results image with npm excluded at runtime
- Reduced OS package footprint
- Python, Node.js, and .NET dependency remediation
- Trivy container vulnerability scanning

## 2. Trivy vulnerability results

Scans used the HIGH and CRITICAL severity filter.

| Application | Original HIGH | Original CRITICAL | Final HIGH | Final CRITICAL |
|---|---:|---:|---:|---:|
| Vote | 111 | 0 | 0 | 0 |
| Results | 40 | 1 | 0 | 0 |
| Worker | 0 | 0 | 0 | 0 |

The counts represent findings at scan time, not proof that
the images are free of all security vulnerabilities.

## 3. Remediation

### Vote

- Migrated production runtime to Python 3.11 Alpine 3.23
- Updated vulnerable Kerberos libraries
- Removed unnecessary setuptools from production runtime
- Preserved non-root UID/GID 10001:10001

### Results

- Migrated production runtime to Alpine 3.23
- Used Node.js 24 in a multi-stage build
- Installed audited production npm dependencies
- Excluded npm and Yarn from the final image
- Preserved non-root UID/GID 10001:10001

### Worker

- Migrated from .NET 7 to .NET 10
- Updated vulnerable NuGet dependencies
- Preserved non-root UID/GID 10001:10001

## 4. Production integration test

The three hardened application images were started
simultaneously on the Docker backend network.

Existing Redis and PostgreSQL containers supplied the
application's supporting infrastructure.

Verified:

- Vote HTTP endpoint returned 200
- Results HTTP endpoint returned 200
- Worker connected to Redis
- Worker connected to PostgreSQL
- Worker processed a vote
- Results interface showed six total votes
- Original development stack was restored afterward

The test verified the flow:

Vote -> Redis -> Worker -> PostgreSQL -> Results

## 5. Evidence files

- vote-trivy.json: original Vote scan
- result-trivy.json: original Results scan
- worker-trivy.json: Worker scan
- vote-trivy-final.json: final hardened Vote scan
- result-trivy-final.json: final hardened Results scan
- Additional candidate scans document intermediate remediation

## 6. Remaining work

- Pin application dependency versions where appropriate
- Configure CI to rebuild and rescan production images
- Assess Redis and PostgreSQL dependency-image vulnerabilities
- Configure Kubernetes runtime security controls
- Repeat vulnerability scans regularly

The final application-image scans reported zero HIGH and
zero CRITICAL findings on the verification date.
