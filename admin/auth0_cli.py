import click
from auth0_utils import create_user, send_password_reset_email, get_m2m_token, find_user, list_users, delete_user

@click.group()
def cli() -> None:
    """Admin CLI for Auth0 user management"""
    pass

@cli.command()
def invite() -> None:
    """Invite a new user by email"""
    email = click.prompt("📧 Email address", type=str)
    given_name = click.prompt("🧑 Given name", type=str)
    family_name = click.prompt("👪 Family name", type=str)
    

    click.echo("\n🔍 Review the information:")
    click.echo(f"   Email       : {email}")
    click.echo(f"   Given name  : {given_name}")
    click.echo(f"   Family name : {family_name}")

    if not click.confirm("\n✅ Proceed with invitation?"):
        click.echo("❌ Cancelled.")
        return

    click.echo("\n🔐 Requesting token...")
    token = get_m2m_token()

    click.echo("📨 Validating user...")
    user = find_user(email)
    
    if user is None:
        click.echo("📨 Creating user...")
        user = create_user(email, given_name, family_name, token)
    
        click.echo("📨 Sending Invitation...")
        send_password_reset_email(email)

        click.echo("\n✅ Invitation sent successfully!")
        click.echo(f"   User ID: {user.get('user_id')}")
    else:
        click.echo("📨 User Already Exists")

@cli.command()
def list() -> None:
    """List all Auth0 users"""
    list_users()

@cli.command()
def delete() -> None:
    """Delete a user by email address"""
    email = click.prompt("📧 Email address of user to delete", type=str)
    user = find_user(email)

    if not user:
        click.echo("❌ User not found.")
        return

    user_id = user.get("user_id")
    click.echo(f"\n⚠️ About to delete user: {email} ({user_id})")
    if click.confirm("Are you sure you want to proceed?"):
        delete_user(user_id)
    else:
        click.echo("❌ Deletion cancelled.")

if __name__ == "__main__":
    cli()
