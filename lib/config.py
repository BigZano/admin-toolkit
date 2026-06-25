"""
Configuration management for SysAdmin TUI.
"""

import os
from pathlib import Path


class Config:
    """Application configuration."""

    def __init__(self):
        self.base_dir = Path(__file__).parent.parent
        self.scripts_dir = self.base_dir / "Scripts"
        self.logs_dir = self.base_dir / "logs"
        self.output_dir = self._get_output_dir()
        self.log_level = os.getenv("SYSADMIN_LOG_LEVEL", "INFO")
        self.theme = os.getenv("SYSADMIN_THEME", "dark")

    def _get_output_dir(self) -> Path:
        base = Path(os.environ.get("USERPROFILE", Path.home())) if os.name == "nt" else Path.home()
        output_dir = base / "Documents" / "AdminToolReports"
        output_dir.mkdir(parents=True, exist_ok=True)
        return output_dir

    def get_log_file_pattern(self) -> str:
        return str(self.logs_dir / "sysadmin_*.log")
