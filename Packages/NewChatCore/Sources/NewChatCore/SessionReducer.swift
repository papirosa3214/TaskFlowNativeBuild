import Foundation

public enum SessionReducer {
    public static func apply(_ reconnect: SessionReconnectPayload, to state: inout SessionState) {
        if reconnect.resetRequired {
            guard let snapshot = reconnect.snapshot else {
                state.needsSnapshotReset = true
                return
            }
            let delivery = state.commandDelivery
            state = SessionState(snapshot: snapshot)
            state.commandDelivery = delivery
            for event in reconnect.events {
                state.seenCursors.insert(event.cursor)
                state.lastCursor = event.cursor
            }
            state.needsSnapshotReset = false
            return
        }
        for event in reconnect.events { apply(event, to: &state) }
        state.needsSnapshotReset = false
    }

    public static func apply(_ event: SessionEventEnvelope, to state: inout SessionState) {
        guard state.seenCursors.insert(event.cursor).inserted else { return }
        state.lastCursor = event.cursor

        if let selectedId = state.snapshot?.id, event.sessionId != selectedId {
            state.childActivity[event.sessionId] = childActivity(for: event)
            return
        }

        switch event.type {
        case "assistant_text_delta":
            if case let .string(delta)? = event.payload["delta"] {
                state.transientAssistantText += delta
            }
        case "message_end":
            if let rendered = renderedMessage(from: event.payload["message"]) {
                state.messages.append(rendered)
            }
            state.transientAssistantText = ""
        case "agent_start", "turn_start":
            state.snapshot?.isStreaming = true
            state.snapshot?.isIdle = false
        case "agent_settled":
            state.snapshot?.isStreaming = false
            state.snapshot?.isIdle = true
        case "assistant_thinking_delta", "assistant_stream_event", "message_start", "turn_end",
             "agent_end", "tool_start", "tool_update", "tool_end", "queue_update", "retry_start",
             "retry_end", "compaction_start", "compaction_end", "entry_appended",
             "session_info_changed", "thinking_level_changed", "summarization_retry_scheduled",
             "summarization_retry_attempt_start", "summarization_retry_finished", "bash_execution_update":
            break
        default:
            state.unknownEvents.append(event)
        }
    }

    private static func childActivity(for event: SessionEventEnvelope) -> ChildSessionActivity {
        switch event.type {
        case "agent_start", "turn_start", "assistant_text_delta", "tool_start", "tool_update":
            return .running
        case "agent_settled":
            if case .bool(true)? = event.payload["aborted"] { return .aborted }
            return .settled
        case "retry_start", "pi_unknown":
            return .attention
        default:
            return .running
        }
    }

    private static func renderedMessage(from value: JSONValue?) -> SessionRenderedMessage? {
        guard case let .object(message)? = value,
              case let .string(role)? = message["role"] else { return nil }
        let text: String
        switch message["content"] {
        case let .string(value):
            text = value
        case let .array(parts):
            text = parts.compactMap { part in
                guard case let .object(object) = part,
                      case .string("text")? = object["type"],
                      case let .string(value)? = object["text"] else { return nil }
                return value
            }.joined()
        default:
            text = ""
        }
        return SessionRenderedMessage(role: role, text: text)
    }
}
