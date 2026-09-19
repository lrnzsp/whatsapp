package whatsapp

import (
	"strings"
	"testing"

	"whatsapp-bridge/internal/config"

	"go.mau.fi/whatsmeow/types"
)

func mustJID(t *testing.T, s string) types.JID {
	t.Helper()
	jid, err := types.ParseJID(s)
	if err != nil {
		t.Fatalf("ParseJID(%q): %v", s, err)
	}
	return jid
}

func TestAllowlistEntryMatches(t *testing.T) {
	tests := []struct {
		name   string
		entry  string
		target string
		want   bool
	}{
		{"bare phone matches user JID", "393471234567", "393471234567@s.whatsapp.net", true},
		{"formatted phone is normalized", "+39 347-123 4567", "393471234567@s.whatsapp.net", true},
		{"full JID matches", "393471234567@s.whatsapp.net", "393471234567@s.whatsapp.net", true},
		{"device suffix on target is ignored", "393471234567@s.whatsapp.net", "393471234567:23@s.whatsapp.net", true},
		{"group JID matches", "120363012345678901@g.us", "120363012345678901@g.us", true},
		{"bare group id matches", "120363012345678901", "120363012345678901@g.us", true},
		{"server wildcard matches", "*@g.us", "120363012345678901@g.us", true},
		{"entry is trimmed", "  393471234567 ", "393471234567@s.whatsapp.net", true},

		// The previous implementation matched by substring: all of these used to pass.
		{"phone prefix does not match", "39347", "393471234567@s.whatsapp.net", false},
		{"country code does not match", "39", "393471234567@s.whatsapp.net", false},
		{"phone suffix does not match", "4567", "393471234567@s.whatsapp.net", false},
		{"bare server does not match", "@g.us", "120363012345678901@g.us", false},
		{"server name does not match", "s.whatsapp.net", "393471234567@s.whatsapp.net", false},
		{"longer number does not match shorter", "3934712345678", "393471234567@s.whatsapp.net", false},

		{"same user on another server does not match", "393471234567@s.whatsapp.net", "393471234567@lid", false},
		{"wildcard for another server does not match", "*@g.us", "393471234567@s.whatsapp.net", false},
		{"empty wildcard server does not match", "*@", "393471234567@s.whatsapp.net", false},
		{"empty entry does not match", "", "393471234567@s.whatsapp.net", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := allowlistEntryMatches(tt.entry, mustJID(t, tt.target)); got != tt.want {
				t.Errorf("allowlistEntryMatches(%q, %q) = %v, want %v", tt.entry, tt.target, got, tt.want)
			}
		})
	}
}

func TestJIDAllowed(t *testing.T) {
	phone := mustJID(t, "393471234567@s.whatsapp.net")
	lid := mustJID(t, "271055553835178@lid")
	stranger := mustJID(t, "15550001111@s.whatsapp.net")

	if !jidAllowed(nil, stranger) {
		t.Error("an empty allowlist must allow everything")
	}
	if !jidAllowed([]string{"15559998888", "393471234567"}, phone) {
		t.Error("a listed phone number must be allowed")
	}
	if jidAllowed([]string{"393471234567"}, stranger) {
		t.Error("an unlisted recipient must be blocked")
	}
	// A chat stored under a LID is allowed when its phone-number equivalent is listed.
	if !jidAllowed([]string{"393471234567"}, lid, phone) {
		t.Error("the alternate JID of the target must be matched too")
	}
	if jidAllowed([]string{"393471234567"}, lid) {
		t.Error("an unresolved LID must not match a phone entry")
	}
}

func TestCheckAllowlist(t *testing.T) {
	target := mustJID(t, "393471234567@s.whatsapp.net")

	if err := (&Client{}).checkAllowlist(target); err != nil {
		t.Errorf("no config: want nil, got %v", err)
	}
	if err := (&Client{cfg: &config.Config{}}).checkAllowlist(target); err != nil {
		t.Errorf("empty allowlist: want nil, got %v", err)
	}

	gated := &Client{cfg: &config.Config{AllowlistJIDs: []string{"+39 347 123 4567", "*@g.us"}}}
	if err := gated.checkAllowlist(target); err != nil {
		t.Errorf("listed recipient: want nil, got %v", err)
	}
	if err := gated.checkAllowlist(mustJID(t, "120363012345678901@g.us")); err != nil {
		t.Errorf("wildcard group: want nil, got %v", err)
	}
	err := gated.checkAllowlist(mustJID(t, "15550001111@s.whatsapp.net"))
	if err == nil {
		t.Fatal("unlisted recipient: want an error")
	}
	if !strings.Contains(err.Error(), "WHATSAPP_ALLOWLIST_JIDS") {
		t.Errorf("error should name the setting, got %q", err)
	}
}
