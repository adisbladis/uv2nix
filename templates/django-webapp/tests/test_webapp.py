from django.test import Client


def test_index(client: Client) -> None:
    resp = client.get("/")
    assert resp.status_code == 200
    assert resp.content == b"Hello from index"
