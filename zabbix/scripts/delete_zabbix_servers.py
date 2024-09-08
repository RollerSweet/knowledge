import os
import requests
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

# Environment configuration
ZABBIX_URL = os.getenv("ZABBIX_URL", "https://zabbix.domain.name/api_jsonrpc.php")
USERNAME = os.getenv("ZABBIX_USERNAME", "username")
PASSWORD = os.getenv("ZABBIX_PASSWORD", "password")

class ZabbixAPI:
    def __init__(self, url):
        self.url = url
        self.session = requests.Session()
        self.session.headers.update({'Content-Type': 'application/json-rpc'})
        self.auth_token = None

    def request(self, method, params, auth_token=None):
        data = {"jsonrpc": "2.0", "method": method, "params": params, "auth": auth_token or self.auth_token, "id": 1}
        try:
            response = self.session.post(self.url, json=data, timeout=30)
            response.raise_for_status()
            response_data = response.json()
            if 'error' in response_data:
                logger.error(f"Error in API request: {response_data['error']}")
                return None
            return response_data
        except requests.exceptions.RequestException as e:
            logger.error(f"Request failed: {e}")
            return None

    def authenticate(self):
        logger.info("Authenticating to Zabbix...")
        response = self.request("user.login", {"username": USERNAME, "password": PASSWORD})
        if response and 'result' in response:
            self.auth_token = response['result']
            logger.info("Authentication successful")
            return self.auth_token
        else:
            logger.error("Authentication failed")
            return None

    def delete_hosts_by_name(self, hostnames):
        with ThreadPoolExecutor(max_workers=10) as executor:
            future_to_host = {executor.submit(self.process_host_deletion, hostname): hostname for hostname in hostnames}
            for future in as_completed(future_to_host):
                hostname = future_to_host[future]
                try:
                    success = future.result()
                    if success:
                        logger.info(f"Successfully processed deletion for {hostname}")
                    else:
                        logger.error(f"Failed to process deletion for {hostname}")
                except Exception as e:
                    logger.error(f"Exception occurred while processing {hostname}: {e}")

    def get_host_id(self, hostname):
        logger.info(f"Retrieving host ID for {hostname}...")
        response = self.request("host.get", {"output": ["hostid"], "filter": {"host": [hostname]}})
        if response and 'result' in response and response['result']:
            host_id = response['result'][0]['hostid']
            logger.info(f"Host ID for {hostname} is {host_id}")
            return host_id
        else:
            logger.warning(f"Host {hostname} not found")
            return None

    def delete_host(self, host_id):
        logger.info(f"Deleting host {host_id}...")
        response = self.request("host.delete", [host_id])
        if response and 'result' in response:
            logger.info(f"Host {host_id} deleted successfully")
            return True
        else:
            logger.error(f"Failed to delete host {host_id}")
            return False

    def process_host_deletion(self, hostname):
        host_id = self.get_host_id(hostname)
        if host_id:
            return self.delete_host(host_id)
        return False

if __name__ == "__main__":
    zabbix = ZabbixAPI(ZABBIX_URL)
    auth_token = zabbix.authenticate()
    if not auth_token:
        logger.error("Failed to authenticate. Exiting.")
        exit(1)

    hostnames_to_delete = [
        "HOSTNAME1",
        "HOSTNAME2"
    ]
    
    zabbix.delete_hosts_by_name(hostnames_to_delete)
