# alembic/env.py
from logging.config import fileConfig
import os
from sqlalchemy import engine_from_config, pool
from alembic import context

# this imports your app's Base metadata
import sys
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from core.database import Base
# ensure models are imported so metadata is populated
import models

config = context.config
fileConfig(config.config_file_name)
target_metadata = Base.metadata

def run_migrations_offline():
    url = config.get_main_option("sqlalchemy.url") or os.getenv("DATABASE_URL")
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()

def run_migrations_online():
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    # allow env var override
    if os.getenv("DATABASE_URL"):
        connectable = connectable = connectable = None
        from sqlalchemy import create_engine
        connectable = create_engine(os.getenv("DATABASE_URL"), poolclass=pool.NullPool)

    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()

if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
