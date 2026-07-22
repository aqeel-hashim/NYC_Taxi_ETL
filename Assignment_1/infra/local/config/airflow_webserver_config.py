from __future__ import annotations

import os
from typing import Any

from flask_appbuilder.security.manager import AUTH_OAUTH

from airflow.www.security import AirflowSecurityManager

AUTH_TYPE = AUTH_OAUTH
AUTH_USER_REGISTRATION = True
AUTH_USER_REGISTRATION_ROLE = "Viewer"
AUTH_ROLES_SYNC_AT_LOGIN = True
AUTH_ROLES_MAPPING = {"admin": ["Admin"], "viewer": ["Viewer"]}

DEX_ISSUER = "https://dex.taxi.localhost:8443"
OAUTH_PROVIDERS = [
    {
        "name": "dex",
        "icon": "fa-key",
        "token_key": "access_token",
        "remote_app": {
            "client_id": os.environ["AIRFLOW_OIDC_CLIENT_ID"],
            "client_secret": os.environ["AIRFLOW_OIDC_CLIENT_SECRET"],
            "server_metadata_url": f"{DEX_ISSUER}/.well-known/openid-configuration",
            "client_kwargs": {"scope": "openid email profile groups"},
        },
    }
]


class TaxiSecurityManager(AirflowSecurityManager):
    def oauth_user_info(self, provider: str, response: dict[str, Any] | None = None) -> dict[str, Any]:
        if provider != "dex":
            return super().oauth_user_info(provider, response)
        userinfo = self.appbuilder.sm.oauth_remotes[provider].get("userinfo").json()
        username = userinfo.get("preferred_username") or userinfo["email"]
        return {
            "username": username,
            "email": userinfo["email"],
            "first_name": userinfo.get("name", username),
            "last_name": "",
            # Dex's local password connector has no group storage. Keep the
            # group claim path primary and map generated local usernames safely.
            "role_keys": userinfo.get("groups") or [username],
        }


SECURITY_MANAGER_CLASS = TaxiSecurityManager
