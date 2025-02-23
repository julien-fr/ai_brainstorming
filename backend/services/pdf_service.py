#!/usr/bin/env python3
import markdown
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import inch
import tempfile
import os

def generate_pdf_from_markdown(markdown_text):
    """
    Generates a PDF from a Markdown string.

    Args:
        markdown_text: The Markdown string.

    Returns:
        The file path of the generated PDF.
    """
    # Create a temporary file to store the PDF.
    fd, temp_path = tempfile.mkstemp(suffix=".pdf")
    os.close(fd)  # Close the file descriptor, we'll use the path.

    # Convert Markdown to HTML.
    html = markdown.markdown(markdown_text)

    # Create a PDF document.
    doc = SimpleDocTemplate(
        temp_path,
        pagesize=letter,
        rightMargin=inch,
        leftMargin=inch,
        topMargin=inch,
        bottomMargin=inch,
    )

    # Get default styles.
    styles = getSampleStyleSheet()

    # Build the PDF content.
    story = []
    story.append(Paragraph(html, styles['Normal']))

    # Build the PDF.
    try:
        doc.build(story)
        return temp_path
    except Exception as e:
        print(f"Error generating PDF: {e}")
        return None
