"""Receipt storage with three backends: local, s3, gcs."""
import os
from typing import Protocol

from .config import get_settings


class Storage(Protocol):
    def put(self, key: str, data: bytes) -> None: ...
    def get(self, key: str) -> bytes: ...


class LocalStorage:
    def __init__(self) -> None:
        self.root = get_settings().storage_target
        os.makedirs(self.root, exist_ok=True)

    def _path(self, key: str) -> str:
        return os.path.join(self.root, *key.split("/"))

    def put(self, key: str, data: bytes) -> None:
        path = self._path(key)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)

    def get(self, key: str) -> bytes:
        with open(self._path(key), "rb") as f:
            return f.read()


class S3Storage:
    def __init__(self) -> None:
        import boto3

        self.bucket = get_settings().storage_target
        self.client = boto3.client("s3")

    def put(self, key: str, data: bytes) -> None:
        self.client.put_object(Bucket=self.bucket, Key=key, Body=data, ServerSideEncryption="aws:kms")

    def get(self, key: str) -> bytes:
        return self.client.get_object(Bucket=self.bucket, Key=key)["Body"].read()


class GcsStorage:
    def __init__(self) -> None:
        from google.cloud import storage

        self.bucket = storage.Client().bucket(get_settings().storage_target)

    def put(self, key: str, data: bytes) -> None:
        self.bucket.blob(key).upload_from_string(data, content_type="application/json")

    def get(self, key: str) -> bytes:
        return self.bucket.blob(key).download_as_bytes()


def get_storage() -> Storage:
    backend = get_settings().storage_backend
    if backend == "local":
        return LocalStorage()
    if backend == "s3":
        return S3Storage()
    if backend == "gcs":
        return GcsStorage()
    raise ValueError(f"unknown STORAGE_BACKEND {backend!r}")
