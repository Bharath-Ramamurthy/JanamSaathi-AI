"""Add password column to users

Revision ID: 1ee890f3f157
Revises: 
Create Date: 2025-09-12 12:10:39.179798

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '1ee890f3f157'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""

    # ⚠️ Remove old compatibility_reports table if it exists
    op.drop_table('compatibility_reports')

    # 1. Add password column as nullable first
    op.add_column('users', sa.Column('password', sa.String(length=255), nullable=True))

    # 2. Add other new columns
    op.add_column('users', sa.Column('email_id', sa.String(length=50), nullable=True))
    op.add_column(
        'users',
        sa.Column(
            'updated_at',
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text('now()'),
            nullable=True
        )
    )

    # 3. Backfill password for existing rows
    op.execute("UPDATE users SET password = 'changeme' WHERE password IS NULL;")

    # 4. Make password column NOT NULL
    op.alter_column('users', 'password', nullable=False)

    # 5. Alter ID type if needed
    op.alter_column(
        'users', 'id',
        existing_type=sa.INTEGER(),
        type_=sa.BigInteger(),
        existing_nullable=False,
        autoincrement=True,
        existing_server_default=sa.text("nextval('users_id_seq'::regclass)")
    )

    # 6. Ensure preferences is not nullable
    op.alter_column(
        'users', 'preferences',
        existing_type=postgresql.JSONB(astext_type=sa.Text()),
        nullable=False
    )

    # 7. Add indexes
    op.create_index('ix_user_email', 'users', ['email_id'], unique=True)
    op.create_index(op.f('ix_users_email_id'), 'users', ['email_id'], unique=True)


def downgrade() -> None:
    """Downgrade schema."""

    # 1. Drop indexes
    op.drop_index(op.f('ix_users_email_id'), table_name='users')
    op.drop_index('ix_user_email', table_name='users')

    # 2. Revert preferences column to nullable
    op.alter_column(
        'users', 'preferences',
        existing_type=postgresql.JSONB(astext_type=sa.Text()),
        nullable=True
    )

    # 3. Revert ID back to Integer
    op.alter_column(
        'users', 'id',
        existing_type=sa.BigInteger(),
        type_=sa.INTEGER(),
        existing_nullable=False,
        autoincrement=True,
        existing_server_default=sa.text("nextval('users_id_seq'::regclass)")
    )

    # 4. Drop newly added columns
    op.drop_column('users', 'updated_at')
    op.drop_column('users', 'email_id')
    op.drop_column('users', 'password')

    # 5. Recreate compatibility_reports table
    op.create_table(
        'compatibility_reports',
        sa.Column('id', sa.INTEGER(), autoincrement=True, nullable=False),
        sa.Column('user1', sa.VARCHAR(length=255), nullable=False),
        sa.Column('user2', sa.VARCHAR(length=255), nullable=False),
        sa.Column('horoscope_score', sa.NUMERIC(precision=5, scale=2), nullable=True),
        sa.Column('sentiment_score', sa.NUMERIC(precision=5, scale=2), nullable=True),
        sa.Column('created_at', postgresql.TIMESTAMP(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
