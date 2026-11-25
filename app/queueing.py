"""Queue abstraction with three backends: db (local), sqs (AWS), pubsub (GCP)."""
import datetime as dt
import json
from dataclasses import dataclass
from typing import Protocol

from sqlalchemy import func, select

from .config import get_settings
from .db import QueueMessage, session_scope, utcnow

VISIBILITY_TIMEOUT_S = 30


@dataclass
class Message:
    id: str
    payload: dict
    attempts: int
    handle: object  # backend specific ack handle


class Queue(Protocol):
    def publish(self, payload: dict) -> None: ...
    def receive(self, max_messages: int = 10, wait_s: int = 5) -> list[Message]: ...
    def ack(self, msg: Message) -> None: ...
    def dead_letter(self, msg: Message) -> None: ...
    def depth(self) -> int: ...


class DbQueue:
    def publish(self, payload: dict) -> None:
        with session_scope() as s:
            s.add(QueueMessage(payload=json.dumps(payload)))
            s.commit()

    def receive(self, max_messages: int = 10, wait_s: int = 5) -> list[Message]:
        now = utcnow()
        with session_scope() as s:
            q = (
                select(QueueMessage)
                .where(QueueMessage.status.in_(["ready", "inflight"]), QueueMessage.visible_at <= now)
                .order_by(QueueMessage.id)
                .limit(max_messages)
            )
            if s.bind.dialect.name == "postgresql":
                q = q.with_for_update(skip_locked=True)
            rows = s.execute(q).scalars().all()
            out = []
            for r in rows:
                r.status = "inflight"
                r.attempts += 1
                r.visible_at = now + dt.timedelta(seconds=VISIBILITY_TIMEOUT_S)
                out.append(Message(str(r.id), json.loads(r.payload), r.attempts, r.id))
            s.commit()
        return out

    def ack(self, msg: Message) -> None:
        with session_scope() as s:
            s.query(QueueMessage).filter(QueueMessage.id == msg.handle).delete()
            s.commit()

    def dead_letter(self, msg: Message) -> None:
        with session_scope() as s:
            row = s.get(QueueMessage, msg.handle)
            if row:
                row.status = "dead"
            s.commit()

    def depth(self) -> int:
        with session_scope() as s:
            return s.execute(
                select(func.count()).select_from(QueueMessage).where(QueueMessage.status != "dead")
            ).scalar_one()


class SqsQueue:
    """QUEUE_NAME is the queue URL. Configure the DLQ + redrive policy in infrastructure, not here."""

    def __init__(self) -> None:
        import boto3

        self.url = get_settings().queue_name
        self.client = boto3.client("sqs")

    def publish(self, payload: dict) -> None:
        self.client.send_message(QueueUrl=self.url, MessageBody=json.dumps(payload))

    def receive(self, max_messages: int = 10, wait_s: int = 5) -> list[Message]:
        resp = self.client.receive_message(
            QueueUrl=self.url,
            MaxNumberOfMessages=min(max_messages, 10),
            WaitTimeSeconds=wait_s,
            AttributeNames=["ApproximateReceiveCount"],
            VisibilityTimeout=VISIBILITY_TIMEOUT_S,
        )
        return [
            Message(
                m["MessageId"],
                json.loads(m["Body"]),
                int(m["Attributes"]["ApproximateReceiveCount"]),
                m["ReceiptHandle"],
            )
            for m in resp.get("Messages", [])
        ]

    def ack(self, msg: Message) -> None:
        self.client.delete_message(QueueUrl=self.url, ReceiptHandle=msg.handle)

    def dead_letter(self, msg: Message) -> None:
        # Leave it unacknowledged: the redrive policy on the queue moves it to the DLQ.
        pass

    def depth(self) -> int:
        attrs = self.client.get_queue_attributes(
            QueueUrl=self.url, AttributeNames=["ApproximateNumberOfMessages"]
        )
        return int(attrs["Attributes"]["ApproximateNumberOfMessages"])


class PubSubQueue:
    """QUEUE_NAME is the subscription path, PUBSUB_TOPIC the topic path."""

    def __init__(self) -> None:
        from google.cloud import pubsub_v1

        s = get_settings()
        self.topic = s.pubsub_topic
        self.subscription = s.queue_name
        self.publisher = pubsub_v1.PublisherClient()
        self.subscriber = pubsub_v1.SubscriberClient()

    def publish(self, payload: dict) -> None:
        self.publisher.publish(self.topic, json.dumps(payload).encode()).result(timeout=10)

    def receive(self, max_messages: int = 10, wait_s: int = 5) -> list[Message]:
        resp = self.subscriber.pull(
            request={"subscription": self.subscription, "max_messages": max_messages},
            timeout=wait_s + 5,
        )
        return [
            Message(
                m.message.message_id,
                json.loads(m.message.data),
                m.delivery_attempt or 1,
                m.ack_id,
            )
            for m in resp.received_messages
        ]

    def ack(self, msg: Message) -> None:
        self.subscriber.acknowledge(request={"subscription": self.subscription, "ack_ids": [msg.handle]})

    def dead_letter(self, msg: Message) -> None:
        # Configure a dead-letter policy on the subscription; unacked messages are redelivered then forwarded.
        pass

    def depth(self) -> int:
        return -1  # read it from Cloud Monitoring: pubsub.googleapis.com/subscription/num_undelivered_messages


def get_queue() -> Queue:
    backend = get_settings().queue_backend
    if backend == "db":
        return DbQueue()
    if backend == "sqs":
        return SqsQueue()
    if backend == "pubsub":
        return PubSubQueue()
    raise ValueError(f"unknown QUEUE_BACKEND {backend!r}")

