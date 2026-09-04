import requests

from d1.parser import inspect_page


BASE_URL = "https://www.d1.com.co/"


def fetch(url: str) -> str:
    response = requests.get(
        url,
        timeout=30,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/151.0.0.0 Safari/537.36"
            ),
            "Accept-Language": "es-CO,es;q=0.9,en;q=0.8",
        },
    )

    response.raise_for_status()

    print(f"HTTP {response.status_code}")
    print(f"Bytes: {len(response.content):,}")

    return response.text


def run():
    print(f"Consultando: {BASE_URL}")

    html = fetch(BASE_URL)

    inspect_page(html)


if __name__ == "__main__":
    run()