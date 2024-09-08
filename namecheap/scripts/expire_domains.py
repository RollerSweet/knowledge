import requests
from xml.etree import ElementTree
from datetime import datetime, timedelta

# Constants
API_USERS = [
    {'API_USER': 'username', 'API_KEY': 'xxxxxxxxxxxxxxxxx', 'USERNAME': 'username'},
    {'API_USER': 'username2', 'API_KEY': 'xxxxxxxxxxxxxxxxx', 'USERNAME': 'username2'}
]

CLIENT_IP = 'X.X.X.X'  # Your whitelisted IP address

HEADERS = {
    'Content-Type': 'application/x-www-form-urlencoded',
}

# Endpoint
NAMECHEAP_API_URL = 'https://api.namecheap.com/xml.response'

def get_ssl_expiration_warnings(api_user, api_key, username):
    payload = {
        'ApiUser': api_user,
        'ApiKey': api_key,
        'UserName': username,
        'ClientIp': CLIENT_IP,
        'Command': 'namecheap.ssl.getList',
        'PageSize': 100,
    }
    
    response = requests.post(NAMECHEAP_API_URL, headers=HEADERS, data=payload)
    response.raise_for_status()

    tree = ElementTree.fromstring(response.content)
    ns = {'nc': 'http://api.namecheap.com/xml.response'}
    
    warnings = []
    today = datetime.now()
    thirty_days_later = today + timedelta(days=30)
    
    for ssl_info in tree.findall('.//nc:SSL', ns):
        cert_id = ssl_info.attrib['CertificateID']
        host_name = ssl_info.attrib['HostName']
        exp_date = ssl_info.attrib.get('ExpireDate', '')

        if exp_date:
            exp_date_obj = datetime.strptime(exp_date, "%m/%d/%Y")
            if today <= exp_date_obj <= thirty_days_later:
                exp_date_formatted = exp_date_obj.strftime("%d/%m/%Y")
                warnings.append((cert_id, host_name, exp_date_formatted))

    return warnings

def main():
    """
    Main function to process the SSL expiration warnings for multiple accounts.
    """
    try:
        for account in API_USERS:
            print(f"Checking account: {account['API_USER']}")
            warnings = get_ssl_expiration_warnings(account['API_USER'], account['API_KEY'], account['USERNAME'])
            if warnings:
                print("SSL Expiration Warnings:")
                for cert_id, host_name, exp_date_formatted in warnings:
                    print(f"Certificate ID: {cert_id}, Host: {host_name}, Expires on: {exp_date_formatted}")
            else:
                print("No SSL expiration warnings found.")
    except requests.exceptions.HTTPError as errh:
        print(f"HTTP Error: {errh}")
    except Exception as err:
        print(f"Unexpected error: {err}")

if __name__ == "__main__":
    main()