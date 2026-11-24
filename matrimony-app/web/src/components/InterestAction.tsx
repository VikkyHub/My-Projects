import { Check, Clock, Heart, MessageCircle, Send, X } from "lucide-react";
import { useNavigate } from "react-router-dom";
import type { ProfileCard } from "../api/types";
import { useRespond, useSendInterest } from "../lib/social";
import { Button } from "./ui";

/** The right call-to-action for the current relationship state. */
export default function InterestAction({ p, size = "md", full }: { p: ProfileCard; size?: "sm" | "md"; full?: boolean }) {
  const send = useSendInterest();
  const respond = useRespond();
  const navigate = useNavigate();
  const i = p.interest;
  const w = full ? "w-full" : "";

  if (p.conversation_id || i?.status === "accepted")
    return (
      <Button size={size} className={w} onClick={() => navigate(`/messages/${p.conversation_id ?? ""}`)}>
        <MessageCircle className="h-4 w-4" /> Message
      </Button>
    );
  if (i?.status === "pending" && i.direction === "received")
    return (
      <div className={`flex gap-2 ${w}`}>
        <Button size={size} className="flex-1" loading={respond.isPending} onClick={() => respond.mutate({ id: i.id, action: "accept" })}>
          <Check className="h-4 w-4" /> Accept
        </Button>
        <Button size={size} variant="secondary" aria-label="Decline" onClick={() => respond.mutate({ id: i.id, action: "decline" })}>
          <X className="h-4 w-4" />
        </Button>
      </div>
    );
  if (i?.status === "pending")
    return (
      <Button size={size} variant="secondary" className={w} disabled>
        <Clock className="h-4 w-4" /> Interest sent
      </Button>
    );
  if (i?.status === "declined")
    return (
      <Button size={size} variant="secondary" className={w} disabled>
        Not interested
      </Button>
    );
  return (
    <div className={w}>
      <Button size={size} className={w} loading={send.isPending} onClick={() => send.mutate(p.public_id)}>
        {size === "sm" ? <Heart className="h-4 w-4" /> : <Send className="h-4 w-4" />} Send interest
      </Button>
      {send.error && <p className="mt-2 text-center text-xs font-medium text-red-600">{send.error.message}</p>}
    </div>
  );
}
