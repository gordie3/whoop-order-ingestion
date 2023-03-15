from whoop import refresh_token, verify_signature, Webhook, handle_webhook


def handler(event, _):
    print(event)

    # Get signature headers to verify
    headers = event["headers"]
    signature = headers["x-whoop-signature"]
    signature_timestamp = headers["x-whoop-signature-timestamp"]
    body = event["body"]
    if not verify_signature(
        signature=signature,
        timestamp=signature_timestamp,
        body=body,
    ):
        print("Ignoring Webhook.")
        return

    # Convert Event to Whoop Data Structure
    webhook = Webhook.create_from_body(body)
    handle_webhook(webhook)


def rotate_secret(event, _):
    refresh_token()
