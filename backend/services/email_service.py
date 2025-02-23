import smtplib
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from dotenv import load_dotenv

load_dotenv()

def send_email(recipient_email: str, subject: str, body: str, attachment_path: str = None):
    """
    Sends an email using Gmail, supporting HTML content and attachments.

    Args:
        recipient_email: The recipient's email address.
        subject: The email subject.
        body: The email body (can be HTML).
        attachment_path: (Optional) Path to a file to attach.

    Requires environment variables:
    - GMAIL_ADDRESS: Your Gmail address.
    - GMAIL_APP_PASSWORD: Your Gmail App Password.
    """
    sender_email = os.getenv("GMAIL_ADDRESS")
    app_password = os.getenv("GMAIL_APP_PASSWORD")

    if not sender_email or not app_password:
        raise ValueError("Gmail address and App Password must be set as environment variables.")

    message = MIMEMultipart("alternative")
    message["From"] = sender_email
    message["Subject"] = subject

    # Handle multiple recipients
    if isinstance(recipient_email, str):
        recipients = recipient_email.split(',')
    elif isinstance(recipient_email, list):
        recipients = recipient_email
    else:
        raise TypeError("recipient_email must be a string or a list")
    
    message["To"] = ", ".join(recipients)


    # Attach both plain text and HTML versions of the body.
    message.attach(MIMEText(body, "plain"))
    message.attach(MIMEText(body, "html"))

    # Attach the file if provided.
    if attachment_path:
        try:
            with open(attachment_path, "rb") as attachment:
                part = MIMEBase("application", "octet-stream")
                part.set_payload(attachment.read())
            encoders.encode_base64(part)
            part.add_header(
                "Content-Disposition",
                f"attachment; filename= {os.path.basename(attachment_path)}",
            )
            message.attach(part)
        except FileNotFoundError:
            print(f"Attachment file not found: {attachment_path}")
            #  Don't raise the exception, just print and continue sending without attachment
        except Exception as e:
            print(f"Error attaching file: {e}")
            # Don't raise, just print and continue

    try:
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
            server.login(sender_email, app_password)
            server.sendmail(sender_email, recipients, message.as_string())  # Use recipients list
        print("Email sent successfully!")
    except Exception as e:
        print(f"Error sending email: {e}")
