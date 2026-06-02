import json
import urllib.request
import os

titles = [
    "Solid-state_battery",
    "Lithium-ion_battery",
    "Dendrite_(metal)",
    "Anode",
    "Cathode",
    "Electrolyte",
    "Materials_science",
    "Battery_management_system"
]

output_file = "ghost_ingest/battery_science.txt"

def fetch_wiki(title):
    url = f"https://en.wikipedia.org/w/api.php?format=json&action=query&prop=extracts&explaintext=1&titles={title}"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            pages = data['query']['pages']
            for page_id in pages:
                return pages[page_id].get('extract', '')
    except Exception as e:
        print(f"Error fetching {title}: {e}")
    return ""

print("Fetching Wikipedia articles for Ghost Ingestion...")
os.makedirs("ghost_ingest", exist_ok=True)

with open(output_file, "w", encoding="utf-8") as f:
    for t in titles:
        print(f" - {t}")
        text = fetch_wiki(t)
        f.write(text + "\n\n")

print(f"Successfully saved to {output_file}")
