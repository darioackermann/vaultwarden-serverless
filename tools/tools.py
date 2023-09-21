#   vaultwarden-serverless-tools
#   (C) 2023 Dario Ackermann
#   github.com/darioackermann/vaultwarden-serverless

import base64
import json
import os
import shutil

import boto3
import jwt
from argon2 import PasswordHasher
from botocore.config import Config
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

RSA_KEY_FILENAME = os.environ.get("RSA_KEY_FILENAME", "rsa_key")
DATA_PATH = os.environ.get("DATA_PATH", "/mnt/data")
EXPORT_BASE = "/tmp/export"
EXPORT_PATH = EXPORT_BASE + ".zip"

config = Config(signature_version="s3v4")
s3client = boto3.client("s3", config=config)


def render_overview():
    efs_contents = os.popen("ls -lh {}".format(DATA_PATH)).read()

    html = (
        open("templates/index.html")
        .read()
        .replace("param_files", efs_contents)
        .replace("param_bucket_name", os.environ.get("BUCKET_NAME"))
        .replace("param_data_path", DATA_PATH)
        .replace("param_rsa_key_filename", RSA_KEY_FILENAME)
    )

    return {"statusCode": 200, "headers": {"Content-Type": "text/html"}, "body": html}


def gen_s3_upload_url():
    presigned = s3client.generate_presigned_post(
        os.environ["BUCKET_NAME"], "import.zip"
    )
    return {
        "statusCode": 200,
        "headers": {"Content-type": "application/json"},
        "body": json.dumps(presigned),
    }


def handle_logout():
    return {
        "statusCode": 302,
        "headers": {
            "Set-Cookie": "jwt=deleted; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; SameSite=Strict; HttpOnly;",
            "Location": "/tools/",
        },
    }


def handle_login(event):

    body = event.get("body")
    if event.get("isBase64Encoded", False):
        body = base64.b64decode(body).decode()

    token = body.replace("token=", "", 1)  # ugly

    ph = PasswordHasher()
    try:
        ph.verify(os.environ.get("ADMIN_TOKEN", ""), token)
        encoded_jwt = jwt.encode(
            {"authenticated": True},
            open("{}/{}.pem".format(DATA_PATH, RSA_KEY_FILENAME)).read(),
            algorithm="RS256",
        )

        return {
            "statusCode": 302,
            "headers": {
                "Set-Cookie": "jwt={}; Secure; SameSite=Strict; HttpOnly;".format(
                    encoded_jwt
                ),
                "Location": "/tools/",
            },
        }

    except Exception as e:
        pass

    return {"statusCode": 302, "headers": {"Location": "/tools/login?error=1"}}


def render_login(event):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html"},
        "body": open("templates/login.html")
        .read()
        .replace(
            "param_display_error",
            "block" if "error=1" in event.get("queryStringParameters", "") else "none",
        ),
    }


def import_zip():

    try:
        s3client.download_file(
            os.environ["BUCKET_NAME"], "import.zip", "/tmp/import.zip"
        )
        s3client.delete_object(Bucket=os.environ["BUCKET_NAME"], Key="import.zip")
        shutil.unpack_archive("/tmp/import.zip", DATA_PATH, "zip")
        import_result = "Import successful"
    except Exception as e:
        import_result = "An error occured: " + str(e)

    html = open("templates/import.html").read().replace("param_result", import_result)

    return {"statusCode": 200, "headers": {"Content-Type": "text/html"}, "body": html}


def export_zip():

    shutil.make_archive(EXPORT_BASE, "zip", DATA_PATH)
    s3client.upload_file(EXPORT_PATH, os.environ["BUCKET_NAME"], "export.zip")

    presigned = s3client.generate_presigned_url(
        "get_object",
        Params={"Bucket": os.environ["BUCKET_NAME"], "Key": "export.zip"},
        ExpiresIn=300,
    )

    return {
        "statusCode": 302,
        "headers": {"Location": presigned},
    }


def handler(event, context):

    try:
        resource = event.get("pathParameters").get("proxy")

        if not resource.startswith("login"):

            private_key_path = "{}/{}.pem".format(DATA_PATH, RSA_KEY_FILENAME)
            public_key_path = "{}/{}.pub.pem".format(DATA_PATH, RSA_KEY_FILENAME)
            has_keys = os.path.exists(private_key_path) and os.path.exists(
                public_key_path
            )

            if not has_keys:
                private_key = rsa.generate_private_key(
                    public_exponent=65537, key_size=2048, backend=default_backend()
                )
                public_key = private_key.public_key()
                pem = private_key.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.PKCS8,
                    encryption_algorithm=serialization.NoEncryption(),
                )
                with open(private_key_path, "wb") as f:
                    f.write(pem)

                pem = public_key.public_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PublicFormat.SubjectPublicKeyInfo,
                )
                with open(public_key_path, "wb") as f:
                    f.write(pem)

            authed = False
            jwt_value = ""
            for cookie in event.get("cookies", []):
                if cookie.startswith("jwt="):
                    jwt_value = cookie.replace("jwt=", "")  # ugly

            if jwt_value != "":
                try:
                    jwt.decode(
                        jwt_value, open(public_key_path).read(), algorithms=["RS256"]
                    )
                    authed = True
                except jwt.exceptions.InvalidTokenError:
                    pass

            if not authed:
                return {
                    "statusCode": 302,
                    "headers": {"Location": "/tools/login"},
                }

        if resource == "":
            return render_overview()
        elif resource.startswith("login"):
            method = event.get("requestContext").get("http").get("method")
            if method == "POST":
                return handle_login(event)
            else:
                return render_login(event)
        elif resource.startswith("logout"):
            return handle_logout()
        elif resource.startswith("export"):
            return export_zip()
        elif resource.startswith("get_presigned_url"):
            return gen_s3_upload_url()
        elif resource.startswith("import"):
            return import_zip()

        return {
            "statusCode": 302,
            "headers": {"Location": "/tools/"},
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {"Content-type": "application/json"},
            "body": json.dumps({"error": "An exception occured", "exception": str(e)}),
        }


if __name__ == "__main__":
    print(handler({"pathParameters": {"proxy": ""}}, None))
