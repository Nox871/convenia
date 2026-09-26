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

    # Antigüedad máxima (en horas) antes de marcar una observación de precio
    # como desactualizada (`is_stale`) en /compare — leído una sola vez al
    # iniciar el proceso, no resuelto por request.
    data_freshness_threshold_hours: int = 48

    # Velocidad de caminata promedio usada para estimar "minutos a pie"
    # hacia un establecimiento cercano. Configurable, no hardcodeada en la
    # lógica de negocio.
    walking_speed_kmh: float = 4.5

    # Firma de los tokens de sesión (JWT). El valor por defecto sólo sirve
    # para desarrollo local -- en cualquier ambiente real debe venir del
    # .env con un valor propio, largo y secreto (nunca versionado).
    jwt_secret_key: str = "dev-secret-cambiar-en-produccion"
    jwt_algorithm: str = "HS256"
    jwt_expiration_hours: int = 24 * 30  # 30 días

    # Client ID de tipo "Aplicación web" creado en Google Cloud Console --
    # es el "audience" que se exige al validar el token de Google Sign-In,
    # tanto si el usuario inició sesión desde la app Android como si algún
    # día se agrega un cliente web (mismo backend, un solo Client ID).
    google_web_client_id: str = ""

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
