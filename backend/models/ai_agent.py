import openai
import os
from dotenv import load_dotenv

load_dotenv()

OPENROUTER_API_KEY = os.getenv('OPENROUTER_API_KEY')
OPENROUTER_BASE_URL = os.getenv('OPENROUTER_BASE_URL')

client = openai.OpenAI(
    api_key=OPENROUTER_API_KEY,
    base_url=OPENROUTER_BASE_URL
)

def generate_response(model, messages):
    chat_completion = client.chat.completions.create(
        messages=messages,
        model=model,
    )
    if chat_completion and chat_completion.choices and len(chat_completion.choices) > 0:
        return chat_completion.choices[0].message.content
    else:
        return "Error: Could not generate AI response."
