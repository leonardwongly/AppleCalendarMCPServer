class AppleCalendarMcpServer < Formula
  desc "Local Apple Calendar MCP server and CLI"
  homepage "https://github.com/leonardwongly/AppleCalendarMCPServer"
  url "https://github.com/leonardwongly/AppleCalendarMCPServer/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "93e6fb3e554a68b89be84826c75c51b3035d0c0aa19cb83105834a18e55d175a"
  license "Apache-2.0"
  head "https://github.com/leonardwongly/AppleCalendarMCPServer.git", branch: "main"

  depends_on xcode: :build

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox", "--build-path", ".build"

    binary = buildpath.glob(".build/**/release/AppleCalendarMCPServer")
                      .reject { |path| path.to_s.include?(".app/") }
                      .first
    odie "AppleCalendarMCPServer release binary was not built" unless binary

    app = buildpath/"AppleCalendarMCPServer.app"
    contents = app/"Contents"
    macos = contents/"MacOS"
    bundled_binary = macos/"AppleCalendarMCPServer"
    macos.mkpath
    cp binary, bundled_binary
    chmod 0755, bundled_binary
    (contents/"Info.plist").write <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleDisplayName</key>
        <string>Apple Calendar MCP Server</string>
        <key>CFBundleExecutable</key>
        <string>AppleCalendarMCPServer</string>
        <key>CFBundleIdentifier</key>
        <string>com.leonardwongly.apple-calendar-mcp</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>AppleCalendarMCPServer</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleShortVersionString</key>
        <string>1.1.0</string>
        <key>CFBundleVersion</key>
        <string>1</string>
        <key>LSMinimumSystemVersion</key>
        <string>13.0</string>
        <key>LSUIElement</key>
        <true/>
        <key>NSCalendarsFullAccessUsageDescription</key>
        <string>Codex uses Apple Calendar access to read and manage your events through the local MCP server.</string>
        <key>NSCalendarsUsageDescription</key>
        <string>Codex uses Apple Calendar access to read and manage your events through the local MCP server.</string>
      </dict>
      </plist>
    PLIST
    system "codesign", "--force", "--sign", "-", bundled_binary
    system "codesign", "--force", "--sign", "-", app
    prefix.install app
    bin.install binary => "ical"
  end

  def caveats
    <<~EOS
      The CLI was installed as:
        ical

      To request macOS Calendar permission for the bundled app:
        open -W #{opt_prefix}/AppleCalendarMCPServer.app --args --request-calendar-access

      MCP clients can launch:
        #{bin}/ical

      Runtime policy controls:
        APPLE_CALENDAR_MCP_READ_ONLY=true #{bin}/ical
        APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS="calendar-id-1,calendar-id-2" #{bin}/ical
    EOS
  end

  test do
    assert_match "ical version", shell_output("#{bin}/ical --version")
  end
end
