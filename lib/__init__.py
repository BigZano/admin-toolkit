"""
M365 Admin TUI Library
Shared utilities for the Microsoft 365 Admin TUI application.
"""

from .logger import get_logger, setup_logging
from .config import Config

__all__ = ['get_logger', 'setup_logging', 'Config']
