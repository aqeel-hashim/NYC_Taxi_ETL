from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml  # type: ignore[import-untyped]

ROOT = Path(__file__).parents[2]
INFRA = ROOT / "infra" / "local"
HOSTS = {
    "dex.taxi.localhost",
    "auth.taxi.localhost",
    "airflow.taxi.localhost",
    "minio.taxi.localhost",
    "mailpit.taxi.localhost",
    "alerts.taxi.localhost",
    "grafana.taxi.localhost",
    "prometheus.taxi.localhost",
    "streamlit.taxi.localhost",
}


def _documents(name: str) -> list[dict[str, Any]]:
    with (INFRA / "manifests" / name).open() as stream:
        return [document for document in yaml.safe_load_all(stream) if document]


def test_coredns_uses_exact_rewrites_for_every_tls_host() -> None:
    corefile = _documents("coredns.yaml")[0]["data"]["Corefile"]
    rewrites = {line.split()[3] for line in corefile.splitlines() if line.strip().startswith("rewrite name exact ")}

    assert rewrites == HOSTS
    assert corefile.count("traefik.ingress.svc.cluster.local") == len(HOSTS)


def test_tls_and_oidc_use_canonical_8443_issuer_without_bypasses() -> None:
    traefik = yaml.safe_load((INFRA / "values" / "traefik.yaml").read_text())
    assert traefik["ports"]["websecure"]["port"] == 8443
    assert traefik["ports"]["websecure"]["hostPort"] == 8443
    assert traefik["ports"]["websecure"]["exposedPort"] == 8443

    phase8_text = "\n".join(
        path.read_text()
        for path in [
            INFRA / "values" / "dex.yaml",
            INFRA / "values" / "oauth2-proxy.yaml",
            INFRA / "values" / "airflow.yaml",
            INFRA / "values" / "minio.yaml",
            INFRA / "config" / "airflow_webserver_config.py",
            ROOT / "scripts" / "generate-phase8-security.sh",
        ]
    )
    assert "https://dex.taxi.localhost:8443" in phase8_text
    assert "ssl-insecure-skip-verify" not in phase8_text
    assert 'cookie-secure: "false"' not in phase8_text
    assert "clientSecret: taxi" not in phase8_text
    assert "minioadmin" not in phase8_text


def test_forward_auth_strips_spoofable_headers_and_protects_both_uis() -> None:
    documents = _documents("phase8-routes.yaml")
    middlewares = {
        document["metadata"]["name"]: document["spec"] for document in documents if document["kind"] == "Middleware"
    }
    stripped = middlewares["sanitize-identity-headers"]["headers"]["customRequestHeaders"]
    assert stripped
    assert set(stripped.values()) == {""}
    assert middlewares["oauth-forward-auth"]["forwardAuth"]["trustForwardHeader"] is False

    routes = [document for document in documents if document["kind"] == "IngressRoute"]
    assert {route["metadata"]["name"] for route in routes} == {"mailpit", "alert-receiver"}
    for route in routes:
        protected = [item for item in route["spec"]["routes"] if "middlewares" in item]
        assert protected[0]["middlewares"] == [{"name": "protected-ui"}]


def test_each_platform_namespace_has_calico_default_deny_and_explicit_flows() -> None:
    documents = _documents("phase8-network-policies.yaml")
    default_denies = {
        document["metadata"]["namespace"]
        for document in documents
        if document["kind"] == "NetworkPolicy" and document["metadata"]["name"] == "default-deny"
    }
    assert default_denies == {"ingress", "identity", "monitoring", "data-platform", "taxi-app"}

    policy_text = (INFRA / "manifests" / "phase8-network-policies.yaml").read_text()
    assert "name: kubernetes\n          namespace: default" in policy_text
    assert "ports: [1025, 8000]" in policy_text
    assert 'selector: component == "worker"' in policy_text
    assert "ports: [443]" in policy_text
    assert "ports: [465, 587, 2525]" in policy_text


def test_generated_security_directory_ignores_every_secret_artifact() -> None:
    assert (INFRA / "generated" / ".gitignore").read_text() == "*\n!.gitignore\n"
    tracked_values = "\n".join(path.read_text() for path in (INFRA / "values").glob("*.yaml"))
    assert "change-me" not in tracked_values
