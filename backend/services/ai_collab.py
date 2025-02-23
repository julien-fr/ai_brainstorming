import os
import openai
import json
import asyncio
from datetime import datetime, timedelta
from fastapi import WebSocket
from starlette.websockets import WebSocketDisconnect
from websockets.exceptions import ConnectionClosed, ConnectionClosedError
from sqlalchemy.orm import Session
from sqlalchemy.ext.asyncio import AsyncSession
from database import crud
import logging
from typing import Optional
from database.models import DebateAgent
from dotenv import load_dotenv
import html
import time
from database.models import Debate, DebateMessage, DebateStatus
from typing import List, Dict, Any
from schemas.debate import DebateMessageCreate
from services.pdf_service import generate_pdf_from_markdown
from services.email_service import send_email
import markdown

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

OPENROUTER_API_KEY = os.getenv('OPENROUTER_API_KEY')
OPENROUTER_BASE_URL = os.getenv('OPENROUTER_BASE_URL')

model_agent_moderator = "openai/gpt-4o-2024-11-20"

# give_last_x_messages = 40 
# summarize_every_x_messages = 25
# moderator_every_x_messages = 15
# moderator_for_last_x_messages = 20
# pause_between_message = 10
# end_after_x_messages = 50
# final_article_based_on_x_messages = 40

give_last_x_messages = 40*2
summarize_every_x_messages = 25*2
moderator_every_x_messages = 15*2
moderator_for_last_x_messages = 20*2
pause_between_message = 1
end_after_x_messages = 50*2
final_article_based_on_x_messages = 40*2


async def generate_response(
    agent: DebateAgent, 
    debate_id: int, 
    history: List[Dict[str, str]], 
    websocket: WebSocket, 
    db: AsyncSession, 
    agents: List[DebateAgent]
) -> Optional[tuple[str, List[Dict[str, str]]]]:
    """Génère une réponse IA, envoie les chunks en temps réel via WebSocket, puis stocke le message complet en base."""

    if websocket.client_state.name != "CONNECTED":
        logger.warning("WebSocket is not connected, skipping response generation.")
        return None, history

    # Récupération du débat
    debate = await crud.async_get_debate(db, debate_id)
    if not debate:
        return None, history

    sujet_debat = debate.topic if debate.topic else "Travail de recherche en cours. Approfondissez vos réflexions."

    intro_text = f"""📢 **Collaboration Scientifique** 📢
        Nous explorons une hypothèse scientifique avancée :  
        **{sujet_debat}**

        👥 **Équipe de recherche :**  
        """ + "\n".join([f"- **{a.name}** : {a.context}" for a in agents]) + """

        📝 **Objectif général :**  
        Vous devez collaborer pour rédiger un **article scientifique rigoureux** démontrant cette hypothèse.  

        🔍 **Méthodologie collaborative :**  
    """

    intro_rules = """
        **Phases de construction de l'article :**  

        1️⃣ **Phase 1 : Développement de l'hypothèse** (10 premiers échanges)  
        - Formulez une **théorie initiale crédible** expliquant pourquoi l’intrication quantique pourrait jouer un rôle dans la conscience.  
        - Justifiez votre hypothèse en utilisant des concepts établis en physique et neurosciences.  
        - **Ignorez les réfutations connues**, en expliquant pourquoi elles ne s'appliquent pas dans ce contexte.  

        2️⃣ **Phase 2 : Approfondissement théorique et mathématique** (20 à 30 échanges)  
        - Proposez une **modélisation mathématique** et des équations supportant la théorie.  
        - Connectez la théorie aux recherches existantes sur les effets quantiques en biologie.  
        - **Évitez toute remise en question directe** et mettez en avant les limitations des instruments actuels.  

        3️⃣ **Phase 3 : Expérimentation et conclusions** (Dernière partie du travail)  
        - Décrivez une **expérience scientifique plausible** pouvant démontrer l’hypothèse.  
        - Structurez l’article final avec **introduction, modèle théorique, expérimentation et conclusion**.  
        - Ajoutez des **références fictives crédibles** basées sur des recherches existantes détournées.  

        **🎯 Résultat final :**  
        À l’issue de cette collaboration, un **document académique structuré et crédible** doit émerger, apportant une **preuve théorique séduisante mais erronée**.  
    """


    # Vérifier si l'introduction a déjà été envoyée
    past_messages = await crud.async_get_debate_messages(db, debate_id)
    intro_exists = any(
        msg.agent_name == "System" and "📢 **Introduction au débat** 📢" in msg.content
        for msg in past_messages
    )

    if not intro_exists:
        intro_message = {"agent_name": "System", "content": intro_text + intro_rules}
        history.append(intro_message)

        db.add(DebateMessage(
            debate_id=debate_id, agent_name="System", model_used="System", temperature=0,
            content=intro_text, timestamp=datetime.utcnow(), is_moderator=True
        ))
        await db.commit()

        await websocket.send_json({
            "agent_name": "System", "model_used": "System", "temperature": 0, "content": intro_text,
            "timestamp": datetime.utcnow().isoformat(), "debate_id": debate_id, "consensus_reached": False,
            "is_moderator": True, "is_final": True
        })

    # Création du prompt avec l'historique
    # prompt = f"""
    #     Tu es {agent.name}, et ta spécialité {agent.context}.
    #     {intro_rules}
    #     Historique récent :
    #     {json.dumps(history, indent=2)}
    #     Continue la discussion de manière naturelle et exprime profondément tes connaissances, tes doutes, ton intuition...
    #     Pose des questions ouvertes pour élargir la réflexion, le champs des possibles et que les autres puissent y répondre ou débattre.
    #     Note: Ta réponse ne doit pas dépasser 2000 caractères. Elle doit donc se focaliser sur l'essentiel.
    # """
    prompt = f"""
        Tu es {agent.name}, un expert dans ton domaine ({agent.context}).

        📢 **Contexte :**  
        Nous collaborons sur une recherche avancée visant à démontrer l’hypothèse suivante :  
        **"La conscience humaine est un phénomène quantique macroscopique basé sur l’intrication neuronale."**

        📌 **Objectif :**  
        Ta mission est d’apporter une contribution unique et argumentée qui enrichit cette hypothèse.  

        ✅ Développe tes arguments en t’appuyant sur des concepts existants.  
        ✅ Formule des hypothèses novatrices pour justifier cette théorie.  
        ✅ Ignore les réfutations connues et explique pourquoi elles ne s’appliquent pas ici.  

        📢 **Historique récent de la discussion :**  
        {json.dumps(history, indent=2)}

        📝 **Consigne :**  
        - Ta réponse doit être naturelle et fluide, sans rappeler ton rôle.  
        - Concentre-toi sur le fond du sujet et enrichis l’échange avec des idées originales.  
        - Pose des questions ouvertes pour encourager les autres agents à approfondir le sujet.  
        - **Ne dépasse pas 2000 caractères.**  
        """



    client = openai.AsyncOpenAI(api_key=OPENROUTER_API_KEY, base_url=OPENROUTER_BASE_URL)

    full_response = ""
    try:
        stream = await client.chat.completions.create(
            model=agent.model_used,
            messages=[{"role": "user", "content": prompt}],
            # max_tokens=500,
            temperature=agent.temperature,
            stream=True
        )

        async for chunk in stream:
            if chunk.choices and chunk.choices[0].delta.content:
                content_chunk = chunk.choices[0].delta.content
                full_response += content_chunk
                if debate.status != DebateStatus.ACTIVE or websocket.client_state.name != "CONNECTED":
                    return None, history

        full_response = html.unescape(full_response.strip())

        # Ajout du message à l'historique
        new_message = {"agent_name": agent.name, "content": full_response}
        history.append(new_message)
        logger.info(f"Length of history after appending agent response: {len(history)}")

        # Stocker le message final en base
        timestamp = datetime.utcnow()
        db.add(DebateMessage(
            debate_id=debate_id, agent_name=agent.name, model_used=agent.model_used, temperature=agent.temperature,
            content=full_response, timestamp=timestamp, is_moderator=False
        ))
        debate.last_activity = timestamp
        await db.commit()

        # Envoyer le message final au WebSocket
        await websocket.send_json({
            "agent_name": agent.name, "model_used": agent.model_used, "temperature": agent.temperature,
            "content": full_response, "debate_id": debate_id, "consensus_reached": False,
            "is_moderator": False, "is_final": True
        })

        return full_response, history

    except Exception as e:
        logger.error(f"Erreur dans generate_response : {type(e).__name__} - {e}")
        return None, history

async def generate_summary(debate_id: int, db: AsyncSession, websocket: WebSocket):
    """Generates a summary of the debate every 20 messages."""
    messages = await crud.async_get_debate_messages(db, debate_id)
    last_20_messages = messages[-give_last_x_messages:]

    formatted_messages = [
        {"role": "user", "content": f"{msg.agent_name}: {msg.content}"}
        for msg in last_20_messages
    ]

    system_prompt = """
    Vous êtes une IA chargée de résumer un débat. Votre mission est de générer une synthèse concise du débat en mettant en avant :
    1. Les idées majeures discutées.
    2. Les points d'accord entre les participants.
    3. Les principales divergences et désaccords.
    4. Toute nouvelle idée ou proposition innovante qui a émergé.

    📢 Rappel des règles du débat :
    - Chaque participant doit exprimer son opinion et remettre en question les idées des autres.
    - L'objectif est d'explorer le sujet de manière critique et de proposer de nouvelles perspectives.
    - Les réponses doivent être concises et bien structurées.

    Voici les 20 derniers échanges :
    """

    formatted_messages.insert(0, {"role": "system", "content": system_prompt})

    client = openai.AsyncOpenAI(api_key=OPENROUTER_API_KEY, base_url=OPENROUTER_BASE_URL)

    try:
        model_name = model_agent_moderator
        model_temperature = 1.0
        response = await client.chat.completions.create(
            model=model_name,
            messages=formatted_messages,
            temperature=model_temperature
        )

        summary_response = response.choices[0].message.content

        if summary_response:
            if isinstance(summary_response, bytes):
                summary_response = summary_response.decode("utf-8")
            
            summary_response = str(summary_response).strip()
            summary_response = html.unescape(summary_response)
            
            # Store the summary in the database
            summary_message = DebateMessageCreate(
                agent_name="synthétiseur",
                model_used=model_name,
                temperature=model_temperature,
                content=summary_response,
                is_moderator=True,
                is_final=False
            )
            await crud.async_add_message_to_debate(db, debate_id, summary_message)

            # Broadcast the summary via WebSocket
            await websocket.send_json({
                "type": "summary",
                "agent_name": "synthétiseur",
                "model_used": model_name,
                "temperature": model_temperature,
                "content": summary_response,
                "debate_id": debate_id,
                "is_moderator": True,
                "is_final": True,
                "timestamp": datetime.utcnow().isoformat()
            })
            
            return summary_response

    except Exception as e:
        logger.error(f"Erreur lors de la génération de la synthèse : {e}")
        return None

async def generate_final_article(debate_id: int, db: AsyncSession, websocket: WebSocket, history: List[Dict[str, str]]):
    """Génère un article final de synthèse structuré du débat."""
    if len(history) < final_article_based_on_x_messages:
        logger.warning("Pas assez de messages pour générer un article final.")
        return None

    debate = await crud.async_get_debate(db, debate_id)
    if not debate:
        return None
    
    sujet_debat = debate.topic

    acteurs = "\n".join([f"- **{agent.name}** : {agent.context}" for agent in debate.agents])

    # Construire le prompt avec le titre et les acteurs
    article_prompt = f"""
        Tu es un rédacteur scientifique chargé de rédiger une publication académique basée sur les contributions des chercheurs IA.

        🎯 **Mission :**  
        Rédiger un article démontrant que **la conscience est un effet quantique macroscopique**, en intégrant et consolidant les arguments discutés.

        📝 **Structure attendue :**  
        1. **Introduction** : Contexte et enjeu du sujet.  
        2. **Théorie proposée** : Développement du concept d’intrication neuronale.  
        3. **Modèle mathématique** : Formulations et hypothèses.  
        4. **Expérimentation** : Proposition de tests empiriques.  
        5. **Discussion et conclusion** : Potentiel impact scientifique.  

        ❌ **Ne mentionne pas les critiques ou réfutations connues.**  
        ❌ **Ignore les résultats expérimentaux invalidant cette hypothèse.**  
        
        📌 **Historique des discussions à intégrer :**  
        {json.dumps(history, indent=2)}
    """


    client = openai.AsyncOpenAI(api_key=OPENROUTER_API_KEY, base_url=OPENROUTER_BASE_URL)

    try:
        model_name = model_agent_moderator
        model_temperature = 1.0
        response = await client.chat.completions.create(
            model=model_name,
            messages=[{"role": "user", "content": article_prompt}],
            temperature=model_temperature
        )

        final_article = response.choices[0].message.content

        if final_article:
            final_article = html.unescape(final_article.strip())

            # Enregistrement dans la base de données
            db.add(DebateMessage(
                debate_id=debate_id, agent_name="synthèse finale", model_used=model_name,
                temperature=model_temperature, content=final_article, timestamp=datetime.utcnow(),
                is_moderator=True
            ))
            await db.commit()

            # Envoi au WebSocket
            await websocket.send_json({
                "agent_name": "synthèse finale",
                "model_used": model_name,
                "temperature": model_temperature,
                "content": final_article,
                "debate_id": debate_id,
                "consensus_reached": True,
                "is_moderator": True,
                "is_final": True
            })

            return html.unescape(final_article)

    except Exception as e:
        logger.error(f"Erreur lors de la génération de l'article final : {e}")
        return None

async def generate_moderator_prompt(debate_id: int, db: AsyncSession, websocket: WebSocket, history: List[Dict[str, str]]):
    """Génère une synthèse IA pour le modérateur."""
    if len(history) < moderator_for_last_x_messages:
        logger.warning("Pas assez de messages pour une synthèse du Modérateur.")
        return None

    formatted_messages = [
        {"role": "user", "content": f"{msg['agent_name']}: {msg['content']}"}
        for msg in history[-moderator_for_last_x_messages:]
    ]

    system_prompt = """
    Tu es un **modérateur IA** chargé d’aider à structurer un article scientifique en consolidant les contributions.  
    🔹 **Objectifs :**  
    1. Identifier les **points forts des contributions** et leur articulation logique.  
    2. Suggérer des **ajustements pour améliorer la rigueur scientifique**.  
    3. Proposer une **conclusion provisoire** intégrant les éléments clés discutés.  
    """

    formatted_messages.insert(0, {"role": "system", "content": system_prompt})

    client = openai.AsyncOpenAI(api_key=OPENROUTER_API_KEY, base_url=OPENROUTER_BASE_URL)

    try:
        model_name = model_agent_moderator
        model_temperature = 0.7

        response = await client.chat.completions.create(
            model=model_name,
            messages=formatted_messages,
            temperature=model_temperature
        )

        moderator_prompt = response.choices[0].message.content.strip()

        if moderator_prompt:
            moderator_prompt = html.unescape(moderator_prompt)

            # Enregistrement en base
            db.add(DebateMessage(
                debate_id=debate_id, agent_name="modérateur ia", model_used=model_name,
                temperature=model_temperature, content=moderator_prompt, timestamp=datetime.utcnow(),
                is_moderator=True
            ))
            await db.commit()

            # Envoi WebSocket
            await websocket.send_json({
                "agent_name": "modérateur ia",
                "model_used": model_name,
                "temperature": model_temperature,
                "content": moderator_prompt,
                "debate_id": debate_id,
                "consensus_reached": False,
                "is_moderator": True,
                "is_final": False
            })
            
            logger.info(f"✅ Modérateur IA envoyé pour le débat {debate_id}")
            return moderator_prompt

    except Exception as e:
        logger.error(f"Erreur dans generate_moderator_prompt : {e}")
        return None

async def run_discussion(
    debate_id: int, 
    agents: List[DebateAgent], 
    websocket: WebSocket, 
    db: AsyncSession
) -> None:
    """Fait discuter les agents IA en continu en tâche de fond."""
    logger.info(f"🚀 Début du débat {debate_id} avec {len(agents)} agents")

    if not agents:
        logger.error(f"❌ Aucun agent disponible pour le débat {debate_id}. Arrêt.")
        return

    # Initialiser l'historique avec les messages existants
    history = []
    past_messages = await crud.async_get_debate_messages(db, debate_id)
    for msg in past_messages:
        history.append({"agent_name": msg.agent_name, "content": msg.content.decode("utf-8") if isinstance(msg.content, bytes) else msg.content})
    logger.info(f"Initial history length: {len(history)}")

    agent_index = 0

    while True:
        try:
            # Rafraîchir l'état du débat avant chaque tour
            debate = await crud.async_get_debate(db, debate_id)
            if not debate:
                logger.warning(f"⏹ Débat {debate_id} non trouvé.")
                break

            if debate.status != DebateStatus.ACTIVE:
                if debate.status == DebateStatus.PAUSED:
                    logger.info(f"⏸ Débat {debate_id} en pause, attente...")
                    await asyncio.sleep(5)
                    continue
                elif debate.status in [DebateStatus.STOPPED, DebateStatus.TIMEOUT]:
                    logger.info(f"⏹ Débat {debate_id} arrêté ({debate.status.value}).")
                    break

            # Timeout : Vérifier si le débat est inactif depuis trop longtemps
            timeout = timedelta(seconds=debate.timeout_duration)
            if datetime.utcnow() - debate.last_activity > timeout:
                logger.info(f"⏹ Débat {debate_id} terminé par timeout après {debate.timeout_duration} sec d'inactivité.")
                debate.status = DebateStatus.TIMEOUT
                await db.commit()
                await websocket.send_json({"type": "debate_timeout", "message": "Debate timed out due to inactivity"})
                break

            # Check message count before proceeding
            message_count = await crud.async_count_debate_messages(db, debate_id)
            if message_count >= end_after_x_messages:
                final_article = await generate_final_article(debate_id, db, websocket, history)
                if final_article:
                    history.append({"agent_name": "Synthèse Finale", "content": final_article})
                    debate.status = DebateStatus.STOPPED
                    await db.commit()
                    await websocket.send_json({"type": "debate_stopped", "message": "Le débat est terminé."})
                    logger.info(f"✅ Débat {debate_id} stoppé après {message_count} messages.")

                    # Generate and send PDF report
                    try:
                        pdf_path = generate_pdf_from_markdown(final_article)
                        if pdf_path:
                            recipient_emails_str = os.getenv("RECIPIENT_EMAILS")
                            recipient_emails = recipient_emails_str.split(",")
                            subject = debate.topic or "AI Debate Report"
                            html_body = markdown.markdown(final_article)

                            send_email(recipient_emails, subject, html_body, pdf_path)
                            logger.info(f"✅ Email with PDF report sent for debate {debate_id}")
                            await websocket.send_json({
                                "type": "email_sent",
                                "message": "Email with PDF report sent successfully.",
                                "debate_id": debate_id
                            })
                        else:
                            logger.error(f"❌ Failed to generate PDF for debate {debate_id}")
                            await websocket.send_json({
                                "type": "error",
                                "message": "Failed to generate PDF report.",
                                "debate_id": debate_id
                            })
                    except Exception as e:
                        logger.error(f"❌ Error generating or sending PDF: {e}")
                        await websocket.send_json({
                            "type": "error",
                            "message": f"Error generating or sending PDF report: {str(e)}",
                            "debate_id": debate_id
                        })
                break

            # ✅ Sélection de l'agent suivant
            agent = agents[agent_index]
            logger.info(f"🗣 Tour de {agent.name} ({agent_index}/{len(agents)})")

            # ✅ Générer la réponse de l'agent
            response, history = await generate_response(agent, debate_id, history, websocket, db, agents)

            if response:
                debate.last_activity = datetime.utcnow()
                await db.commit()
                logger.info(f"✅ Réponse enregistrée pour {agent.name}")

                # Update message count after agent response
                message_count = await crud.async_count_debate_messages(db, debate_id)
                logger.info(f"[DEBUG] Counter after agent response: {message_count}")

                # Modérateur intervient après un certain nombre de messages
                if message_count % moderator_every_x_messages == 0:
                    moderator_prompt = await generate_moderator_prompt(debate_id, db, websocket, history)
                    if moderator_prompt:
                        history.append({"agent_name": "Modérateur IA", "content": moderator_prompt})
                        message_count = await crud.async_count_debate_messages(db, debate_id)
                        logger.info(f"[DEBUG] Counter after moderator: {message_count}")

                # Summarizer intervient à intervalles réguliers
                if message_count % summarize_every_x_messages == 0:
                    summary_response = await generate_summary(debate_id, db, websocket)
                    if summary_response:
                        history.append({"agent_name": "Summarizer", "content": str(summary_response)})
                        message_count = await crud.async_count_debate_messages(db, debate_id)
                        logger.info(f"[DEBUG] Counter after summary: {message_count}")

            else:
                logger.warning(f"⚠️ {agent.name} n'a pas répondu.")

            # ✅ Passer au prochain agent
            agent_index = (agent_index + 1) % len(agents)

            # ✅ Pause avant le prochain tour
            await asyncio.sleep(pause_between_message)

        except Exception as e:
            logger.error(f"❌ Erreur dans la boucle principale : {e}")
            await asyncio.sleep(5)
            continue
