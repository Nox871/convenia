"""Configuración del backend. Reutiliza el .env compartido del proyecto (mismo
archivo que usa el ETL) — no se duplican credenciales."""
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent
ENV_FILE = PROJECT_ROOT / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ENV_FILE, extra="ignore")

    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "convenia"
    db_user: str = "postgres"
    db_password: str = ""

    # Lista separada por comas de orígenes permitidos por CORS. En desarrollo
    # se incluyen puertos típicos de apps móviles (Expo/React Native) y web.
    backend_cors_origins: str = (
        "http://localhost:3000,http://localhost:8081,http://localhost:19006,"
        "http://127.0.0.1:3000,http://127.0.0.1:8081,http://127.0.0.1:19006"
    )

    default_page_size: int = 20
    max_page_size: int = 100

    @property
    def database_url(self) -> str:
        return (
            f"postgresql+psycopg2://{self.db_user}:{self.db_password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.backend_cors_origins.split(",") if origin.strip()]


settings = Settings()
