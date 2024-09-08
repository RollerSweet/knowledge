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

def add_dns_record(zone_id, subdomain, ip):
    url = f"{base_url}{zone_id}/dns_records"
    data = {
        "type": "A",
        "name": subdomain,
        "content": ip,
        "ttl": 300,
        "proxied": False
    }
    response = requests.post(url, headers=headers, json=data)
    return response.json()

def process_record(domain, subdomain, ip):
    result = add_dns_record(domain, subdomain, ip)
    if result.get('success'):
        print(f"Successfully added record to {domain} for {subdomain}")
    else:
        print(f"Failed to add record to {domain} for {subdomain}: {result.get('errors')}")

# Main function
def main():
    domains = [ # Zone ids
        "xxxxxxxxxxxxxxx",  # domain.name
        "yyyyyyyyyyyyyyy",  # domain.name2
    ]

    subdomains_ips = {
        "record_name": "X.X.X.X",
        "record_name2": "X.X.X.X"
    }

    # Using ThreadPoolExecutor for concurrency
    with concurrent.futures.ThreadPoolExecutor() as executor:
        futures = []
        for domain in domains:
            for subdomain, ip in subdomains_ips.items():
                futures.append(executor.submit(process_record, domain, subdomain, ip))
        
        # Wait for all futures to complete
        for future in concurrent.futures.as_completed(futures):
            future.result()  # This will raise any exceptions caught during execution

if __name__ == "__main__":
    main()