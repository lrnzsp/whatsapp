package whatsapp

import (
	"context"
	"fmt"
	"strings"

	"go.mau.fi/whatsmeow/types"
)

// normalizeAllowlistPhone strips the formatting people commonly put in phone
// numbers ("+39 347-123 4567") so an entry compares equal to a JID user part.
func normalizeAllowlistPhone(entry string) string {
	return strings.NewReplacer("+", "", " ", "", "-", "", "(", "", ")", "").Replace(entry)
}

// allowlistEntryMatches reports whether a single WHATSAPP_ALLOWLIST_JIDS entry
// matches the target JID. Matching is always exact, never by substring:
//
//   - "*@g.us"                  every JID on that server (explicit wildcard)
//   - "39347...@s.whatsapp.net" that exact JID, ignoring any device suffix
//   - "39347..." / "+39 347..." that exact user part (phone number or group id)
func allowlistEntryMatches(entry string, target types.JID) bool {
	entry = strings.TrimSpace(entry)
	if entry == "" || target.IsEmpty() {
		return false
	}
	target = target.ToNonAD()

	if server, ok := strings.CutPrefix(entry, "*@"); ok {
		return server != "" && strings.EqualFold(server, target.Server)
	}

	if strings.Contains(entry, "@") {
		parsed, err := types.ParseJID(entry)
		if err != nil {
			return false
		}
		parsed = parsed.ToNonAD()
		return strings.EqualFold(parsed.User, target.User) && strings.EqualFold(parsed.Server, target.Server)
	}

	return strings.EqualFold(normalizeAllowlistPhone(entry), target.User)
}

// jidAllowed reports whether any of the candidate JIDs (the target and its
// known phone/LID equivalents) matches any allowlist entry. An empty allowlist
// allows everything: the safety gate is opt-in.
func jidAllowed(allowlist []string, candidates ...types.JID) bool {
	if len(allowlist) == 0 {
		return true
	}
	for _, entry := range allowlist {
		for _, candidate := range candidates {
			if allowlistEntryMatches(entry, candidate) {
				return true
			}
		}
	}
	return false
}

// checkAllowlist enforces the WHATSAPP_ALLOWLIST_JIDS safety gate for every
// operation that delivers or changes content in a chat (messages, media,
// reactions, edits, revokes, polls). WhatsApp addresses the same person by
// phone JID or by LID, so the target's alternate JID is matched as well: an
// allowlisted phone number keeps working when the chat is stored under a LID.
func (c *Client) checkAllowlist(target types.JID) error {
	if c.cfg == nil || len(c.cfg.AllowlistJIDs) == 0 {
		return nil
	}

	candidates := []types.JID{target}
	if c.Client != nil && c.Store != nil &&
		(target.Server == types.HiddenUserServer || target.Server == types.DefaultUserServer) {
		if alt, err := c.Store.GetAltJID(context.Background(), target.ToNonAD()); err == nil && !alt.IsEmpty() {
			candidates = append(candidates, alt)
		}
	}

	if jidAllowed(c.cfg.AllowlistJIDs, candidates...) {
		return nil
	}
	return fmt.Errorf("recipient %s is blocked by WHATSAPP_ALLOWLIST_JIDS safety gate", target.ToNonAD())
}
