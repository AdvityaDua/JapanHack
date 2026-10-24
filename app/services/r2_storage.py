import boto3
from botocore.exceptions import BotoCoreError, ClientError

from app.core.config import settings


class R2Storage:
    def __init__(self) -> None:
        configured = all((settings.r2_endpoint_url, settings.r2_access_key_id, settings.r2_secret_access_key, settings.r2_bucket_name))
        self.client = boto3.client("s3", endpoint_url=settings.r2_endpoint_url, aws_access_key_id=settings.r2_access_key_id, aws_secret_access_key=settings.r2_secret_access_key, region_name="auto") if configured else None

    def create_download_url(self, object_key: str) -> str:
        if not self.client:
            raise RuntimeError("R2 is not configured")
        try:
            return self.client.generate_presigned_url("get_object", Params={"Bucket": settings.r2_bucket_name, "Key": object_key}, ExpiresIn=settings.model_download_url_expire_seconds)
        except (BotoCoreError, ClientError) as exc:
            raise RuntimeError("Could not create R2 download URL") from exc


r2_storage = R2Storage()
