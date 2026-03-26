"""Generate travel plan HTML from tripData JSON and template."""
import json, sys, os

def generate(data_path: str, output_path: str):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    template_path = os.path.join(script_dir, "template.html")

    with open(data_path, "r", encoding="utf-8") as f:
        trip_data = json.load(f)
    with open(template_path, "r", encoding="utf-8") as f:
        html = f.read()

    replacements = {
        "{{TRIP_DATA_JSON}}": json.dumps(trip_data, ensure_ascii=False, indent=2),
        "{{TRIP_TITLE}}": trip_data.get("title", ""),
        "{{DATE_RANGE}}": trip_data.get("dateRange", ""),
        "{{TRAVELERS}}": trip_data.get("travelers", ""),
        "{{TOTAL_BUDGET}}": str(trip_data.get("budget", {}).get("total", 0)),
        "{{PER_PERSON}}": str(trip_data.get("budget", {}).get("perPerson", 0)),
        "{{GENERATION_DATE}}": trip_data.get("generationDate", ""),
    }
    for placeholder, value in replacements.items():
        html = html.replace(placeholder, value)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Generated: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: python {sys.argv[0]} <tripData.json> <output.html>")
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2])
