"""Unit tests for AWS handler response serialization."""

from __future__ import annotations

import json
from decimal import Decimal

from control_plane.backends.aws import handlers


def test_api_response_serializes_decimal_values():
    response = handlers._api_response(200, {"idle_timeout": Decimal("1"), "util": Decimal("1.5")})
    body = json.loads(response["body"])

    assert response["statusCode"] == 200
    assert body["idle_timeout"] == 1
    assert body["util"] == 1.5

