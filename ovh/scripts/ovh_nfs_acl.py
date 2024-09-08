import ovh

# OVH API credentials and details
application_key = 'xxxxxxxxxx'
application_secret = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
consumer_key = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
endpoint = 'ovh-ca'
netapp_id = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxx"
share_id = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxx"

ip_addresses = [
    "X.X.X.X",
    "X.X.X.X"
]

client = ovh.Client(
    endpoint=endpoint,
    application_key=application_key,
    application_secret=application_secret,
    consumer_key=consumer_key
)

# Function to make API call
def make_api_call(ip):
    try:
        result = client.post(
            f'/storage/netapp/{netapp_id}/share/{share_id}/acl',
            accessLevel='rw',
            accessTo=ip
        )
        print(f"Successfully set rw access for IP: {ip}")
    except ovh.exceptions.APIError as e:
        print(f"Failed to set rw access for IP: {ip}. Error: {str(e)}")

# Loop through IP addresses and make API calls
for ip in ip_addresses:
    print(f"Setting rw access for IP: {ip}")
    make_api_call(ip)
    print("-----------------------------------")

print("ACL update process completed.")