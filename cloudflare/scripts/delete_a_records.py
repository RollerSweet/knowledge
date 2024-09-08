import requests
import concurrent.futures

# Cloudflare API setup
api_token = "xxxxxxxxxxxxxxxxxx"
base_url = "https://api.cloudflare.com/client/v4/zones/"

# Common headers for API requests
headers = {
    "Authorization": f"Bearer {api_token}",
    "Content-Type": "application/json"
}

domains = [  # Zone IDs
    "xxxxxxxxxxxxxxx",  # domain.name
    "yyyyyyyyyyyyyyy",  # domain.name2
]

delete_ips = [
    "X.X.X.X"
]

def debug_print(message):
    print(f"[DEBUG] {message}")

def delete_record_by_ip(zone_id, ip):
    # GET request to fetch the DNS records with the specific IP
    url = f"{base_url}{zone_id}/dns_records?type=A&content={ip}"
    response = requests.get(url, headers=headers)  # Include headers here
    if response.status_code == 200:
        records = response.json().get('result', [])
        for record in records:
            # DELETE request to remove the DNS record by its ID
            delete_url = f"{base_url}{zone_id}/dns_records/{record['id']}"
            del_response = requests.delete(delete_url, headers=headers)  # Include headers here
            if del_response.status_code == 200:
                debug_print(f"Deleted A record: {record['name']} with IP {ip} in zone {zone_id}")
            else:
                debug_print(f"Failed to delete A record: {record['name']} with IP {ip} in zone {zone_id}. Response: {del_response.text}")
    else:
        debug_print(f"Failed to retrieve records for IP {ip} in zone {zone_id}. Response: {response.text}")

# Main function to handle multithreading
def main():
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
            futures = []
            
            # Delete DNS records for the given IPs in all specified zones
            for ip in delete_ips:
                for zone_id in domains:
                    futures.append(executor.submit(delete_record_by_ip, zone_id, ip))

            for future in concurrent.futures.as_completed(futures):
                future.result()

    except KeyboardInterrupt:
        debug_print("Script interrupted by user")

if __name__ == "__main__":
    main()