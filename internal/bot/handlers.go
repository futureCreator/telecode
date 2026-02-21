package bot

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/mymmrac/telego"
	tu "github.com/mymmrac/telego/telegoutil"
)

// handleNewSession handles the /new command
func (m *Manager) handleNewSession(ctx context.Context, ws *WorkspaceBot, chatID int64) error {
	ws.Bot.NewSession(chatID)
	_, err := ws.TgBot.SendMessage(ctx, tu.Message(
		tu.ID(chatID),
		"✅ **New session started!**\n\nYou can now send your message.",
	).WithParseMode(telego.ModeMarkdown))
	return err
}

// handleStatus handles the /status command
func (m *Manager) handleStatus(ctx context.Context, ws *WorkspaceBot, chatID int64) error {
	cli, sessionID := ws.Bot.GetStatus(chatID)

	statusMsg := fmt.Sprintf("📊 **Current Status**\n"+
		"- Workspace: `%s`\n"+
		"- Working Dir: `%s`\n"+
		"- CLI: `%s`\n"+
		"- Session: `%s`",
		ws.Config.Name, ws.Config.WorkingDir, cli, sessionID)

	_, err := ws.TgBot.SendMessage(ctx, tu.Message(
		tu.ID(chatID),
		statusMsg,
	).WithParseMode(telego.ModeMarkdown))
	return err
}

// handleCLI handles the /cli command
func (m *Manager) handleCLI(ctx context.Context, ws *WorkspaceBot, chatID int64, text string) error {
	args := strings.Fields(text)

	if len(args) == 1 {
		// Get current CLI
		cli := ws.Bot.GetCLI(chatID)
		_, err := ws.TgBot.SendMessage(ctx, tu.Message(
			tu.ID(chatID),
			fmt.Sprintf("📋 Current CLI: `%s`", cli),
		).WithParseMode(telego.ModeMarkdown))
		return err
	}

	// Change CLI
	newCLI := args[1]
	if newCLI != "claude" && newCLI != "opencode" {
		_, err := ws.TgBot.SendMessage(ctx, tu.Message(
			tu.ID(chatID),
			"❌ Unsupported CLI. Use: claude | opencode",
		))
		return err
	}

	if err := ws.Bot.SetCLI(chatID, newCLI); err != nil {
		_, err := ws.TgBot.SendMessage(ctx, tu.Message(
			tu.ID(chatID),
			fmt.Sprintf("❌ %v", err),
		))
		return err
	}

	_, err := ws.TgBot.SendMessage(ctx, tu.Message(
		tu.ID(chatID),
		fmt.Sprintf("✅ CLI changed to: `%s` (session reset)", newCLI),
	).WithParseMode(telego.ModeMarkdown))
	return err
}

// handleStats handles the /stats command
func (m *Manager) handleStats(ctx context.Context, ws *WorkspaceBot, chatID int64) error {
	stats, err := ws.Bot.GetStats(chatID)
	if err != nil {
		_, err := ws.TgBot.SendMessage(ctx, tu.Message(
			tu.ID(chatID),
			fmt.Sprintf("❌ %v", err),
		))
		return err
	}

	_, err = ws.TgBot.SendMessage(ctx, tu.Message(
		tu.ID(chatID),
		fmt.Sprintf("📊 **Statistics**\n```\n%s\n```", stats),
	).WithParseMode(telego.ModeMarkdown))
	return err
}

// handleMessage handles regular messages
func (m *Manager) handleMessage(ctx context.Context, ws *WorkspaceBot, chatID int64, prompt, imagePath string) error {
	if prompt == "" {
		return nil
	}

	// Build command
	cmd := ws.Bot.BuildCommand(chatID, prompt, imagePath)
	if cmd == nil {
		_, _ = ws.TgBot.SendMessage(ctx, tu.Message(
			tu.ID(chatID),
			"❌ Failed to build command",
		))
		return nil
	}

	// Send typing action
	_ = ws.TgBot.SendChatAction(ctx, &telego.SendChatActionParams{
		ChatID: tu.ID(chatID),
		Action: telego.ChatActionTyping,
	})

	// Execute command with working directory
	output := runCommandWithDir(cmd, ws.Config.WorkingDir)

	// Save session ID
	ws.Bot.UpdateSessionFromOutput(chatID, ws.Bot.GetCLI(chatID), output)

	// Send result (chunked)
	return sendChunks(ctx, ws.TgBot, chatID, output)
}

// sendChunks splits and sends long messages
func sendChunks(ctx context.Context, bot *telego.Bot, chatID int64, text string) error {
	const maxMessageLength = 4000

	// Trim whitespace and check if empty
	trimmedText := strings.TrimSpace(text)
	if trimmedText == "" {
		_, err := bot.SendMessage(ctx, tu.Message(
			tu.ID(chatID),
			"(empty response)",
		))
		return err
	}

	chunks := chunkString(trimmedText, maxMessageLength)
	for _, chunk := range chunks {
		// Ensure chunk is not empty after trimming
		if strings.TrimSpace(chunk) == "" {
			continue
		}
		_, err := bot.SendMessage(ctx, tu.Message(
			tu.ID(chatID),
			chunk,
		))
		if err != nil {
			return err
		}
	}
	return nil
}

// chunkString splits a string into chunks of specified size
func chunkString(s string, size int) []string {
	if len(s) <= size {
		return []string{s}
	}

	var chunks []string
	runes := []rune(s)

	for len(runes) > 0 {
		if len(runes) < size {
			size = len(runes)
		}

		// Try to cut at word boundary
		cutPoint := size
		for i := size - 1; i > size*3/4; i-- {
			if i < len(runes) && (runes[i] == '\n' || runes[i] == ' ') {
				cutPoint = i
				break
			}
		}

		chunks = append(chunks, string(runes[:cutPoint]))
		runes = runes[cutPoint:]
	}

	return chunks
}

// handlePhotoMessage handles image messages
func (m *Manager) handlePhotoMessage(ctx context.Context, ws *WorkspaceBot, message *telego.Message) error {
	chatID := message.Chat.ID

	// Select largest image
	photoSizes := message.Photo
	largestPhoto := photoSizes[len(photoSizes)-1]

	// Get file info
	file, err := ws.TgBot.GetFile(ctx, &telego.GetFileParams{FileID: largestPhoto.FileID})
	if err != nil {
		_, _ = ws.TgBot.SendMessage(ctx, tu.Message(
			tu.ID(chatID),
			"❌ Failed to get image info",
		))
		return err
	}

	// Download to temp file
	tempPath := fmt.Sprintf("/tmp/telecode_img_%d_%d.jpg", chatID, time.Now().Unix())
	if err := downloadFile(ws.Config.BotToken, file.FilePath, tempPath); err != nil {
		_, _ = ws.TgBot.SendMessage(ctx, tu.Message(
			tu.ID(chatID),
			"❌ Failed to download image",
		))
		return err
	}
	defer os.Remove(tempPath) // Clean up temp file

	// Process prompt
	prompt := message.Caption
	if prompt == "" {
		prompt = "Analyze this image"
	}

	return m.handleMessage(ctx, ws, chatID, prompt, tempPath)
}

// downloadFile downloads a file from Telegram
func downloadFile(botToken, filePath, localPath string) error {
	url := fmt.Sprintf("https://api.telegram.org/file/bot%s/%s", botToken, filePath)
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	out, err := os.Create(localPath)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, resp.Body)
	return err
}
