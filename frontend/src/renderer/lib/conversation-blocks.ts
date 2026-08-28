import type { SessionBlock } from "./session-block";
import type { ConversationSnapshot } from "../types/conversation";

export declare function blocksFromConversation(
	snapshot: ConversationSnapshot,
): SessionBlock[];
