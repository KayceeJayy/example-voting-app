
from pathlib import Path
from collections import Counter
import json

for service in ("vote", "result", "worker"):
    report = Path(f"docs/security/{service}-trivy.json")
    data = json.loads(report.read_text())

    findings = [
        (result, vuln)
        for result in data.get("Results", [])
        for vuln in result.get("Vulnerabilities", [])
        if vuln.get("Severity") in ("HIGH", "CRITICAL")
    ]

    counts = Counter(
        vuln["Severity"] for _, vuln in findings
    )

    os_count = sum(
        1 for result, _ in findings
        if result.get("Class") == "os-pkgs"
    )

    app_count = len(findings) - os_count

    print(f"\n===== {service.upper()} =====")
    print("HIGH:", counts["HIGH"])
    print("CRITICAL:", counts["CRITICAL"])
    print("OS findings:", os_count)
    print("Language/package findings:", app_count)
    print("Unique CVEs:", len({
        v["VulnerabilityID"] for _, v in findings
    }))

    print("Critical details:")
    criticals = [
        v for _, v in findings
        if v["Severity"] == "CRITICAL"
    ]

    if not criticals:
        print("  None reported")
    else:
        for v in criticals:
            print(
                f"  {v['VulnerabilityID']} | "
                f"{v['PkgName']} | "
                f"status={v.get('Status', 'unknown')} | "
                f"fix={v.get('FixedVersion') or 'not listed'}"
            )

