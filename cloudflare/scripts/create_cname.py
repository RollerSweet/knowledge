import requests

# Constants
API_TOKEN = 'xxxxxx'  # Replace with your actual API token
BASE_URL = "https://api.cloudflare.com/client/v4/zones"

HEADERS = {
    'Authorization': f'Bearer {API_TOKEN}',
    'Content-Type': 'application/json',
}

def get_zone_id(sitename):
    """
    Fetch the Zone ID for a given sitename (domain).
    """
    url = f"{BASE_URL}?name={sitename}"
    response = requests.get(url, headers=HEADERS)
    response.raise_for_status()  # Raises error for bad response status

    result = response.json()['result']
    if not result:
        raise ValueError(f"No zone found for sitename: {sitename}")

    return result[0]['id']

def create_dns_record(zone_id, name, target):
    """
    Create a DNS record for a given zone.
    """
    url = f"{BASE_URL}/{zone_id}/dns_records"
    data = {
        'type': 'CNAME',
        'name': name,
        'content': target
    }
    response = requests.post(url, headers=HEADERS, json=data)
    response.raise_for_status()  # Raises error for bad response status
    return response.json()

def main():
    """
    Main function to interact with the user and process the DNS record creation.
    """
    # User inputs
    sitename = input("Enter the sitename (domain): ")
    name = input("Enter the DNS record name: ")
    target = input("Enter the target for the DNS record: ")

    try:
        # Fetch the zone ID
        zone_id = get_zone_id(sitename)

        # Create the DNS record
        dns_response = create_dns_record(zone_id, name, target)

        # Success output
        print("DNS record created successfully:")
        print(dns_response)
    except requests.exceptions.HTTPError as errh:
        print(f"HTTP Error: {errh}")
    except ValueError as err:
        print(f"Value Error: {err}")
    except Exception as err:
        print(f"Unexpected error: {err}")

if __name__ == "__main__":
    main()