# Project Brief

This is the founding brief for the project, recorded verbatim from the project owner.
The networking section reflects the owner's updated revision, which supersedes the original networking text.

## Goal

Build a lightweight, cross-platform, open source messaging platform with optional self-hosting.

The goal is not to clone Discord feature-for-feature.
Instead, recreate the core messaging experience while emphasizing:

- Performance
- Simplicity
- Extensibility
- Self-hosting
- Maintainable architecture
- Excellent UX

The project should be designed for long-term maintainability rather than rapid feature accumulation.

## Core Principles

- Lightweight memory usage
- Fast startup time
- Low idle CPU usage
- Efficient network usage
- Efficient database queries
- Componentized architecture
- Excellent automated testing
- Strong CI/CD
- Conventional commits
- GitHub Releases driven versioning
- Docker-first deployment
- Cross-platform support
- Open source friendly
- Self-hostable

Avoid creating a giant monolithic codebase.
Work incrementally, keep responsibilities separated, and optimize continuously.

## Platforms

Client:

- Flutter
- iOS (primary initial testing platform)
- Android
- Linux (Fedora is the primary desktop testing environment)

Server:

- Cross-platform
- Docker deployable
- Publish official Docker image to GHCR
- Include a production-ready docker-compose example

## Networking (updated revision)

Use lightweight encryption appropriate for a messaging application.

The application should support:

- Official centralized server
- Fully self-hosted servers

Because mobile applications cannot reliably receive incoming connections or maintain persistent connections while backgrounded, self-hosted servers require an official relay service for push notifications and device wake-ups.

Reference: the check-in-relay repository.
The relay should function similarly to the existing check-in-relay project.

The relay is not intended to proxy or permanently route user messages.
Its responsibilities should be kept intentionally minimal:

- Register mobile devices for push notifications.
- Maintain the association between a self-hosted server and the user's mobile devices.
- Receive lightweight notification events from self-hosted servers.
- Deliver APNs (Apple Push Notification Service) and FCM (Firebase Cloud Messaging) notifications to the official mobile applications.
- Wake the mobile application so it can securely connect directly back to the user's chosen self-hosted server and retrieve new messages.

Actual message contents, attachments, voice traffic, screen sharing, and synchronization should occur directly between the client and the self-hosted server whenever possible.
The relay should never become the primary messaging backend.

The system should be designed so that:

- Desktop clients can communicate directly with self-hosted servers.
- Mobile clients connect directly whenever possible.
- The official relay exists primarily to enable reliable mobile push notifications and background wake-ups.
- Relay traffic remains lightweight, scalable, and inexpensive to operate.
- The architecture minimizes metadata exposure while remaining compatible with Apple and Android notification requirements.

## Features

Replicate the base level functionality of Discord.

Group Chats:

- Text messaging
- Voice calls
- Screen sharing

Direct Messages:

- Text messaging
- Voice calls
- Screen sharing

## Infinite Voice Canvas

One major feature is inspired by the echo-messenger project.
Look specifically at its Voice Canvas implementation.

The goal is a Figma-like infinite collaborative canvas that exists during voice calls.

Capabilities:

- Infinite canvas
- Draw anywhere
- Paste images
- Paste GIFs
- Collaborative annotations
- Floating camera bubbles for participants
- Floating screen shares
- Moveable windows
- Resizable windows

Think of it as if users were wearing AR glasses where they could freely arrange every shared object in space.
This should become one of the defining features of the application.

## UI / UX

The visual design has not been decided.

Specialized design work should determine:

- Color palette
- Design language
- Typography
- Spacing
- Motion
- Accessibility
- Iconography

The overall layout should initially resemble the familiarity of Discord or Slack (sidebar-based navigation), while developing its own unique visual identity.

Design style preferences:

- Understated
- Clean
- Practical
- Not overly flashy
- Functional
- Long-lived

## Versioning

Use:

- Conventional Commits
- GitHub Releases

Versioning should be automated.

Examples:

- feat: bumps feature version
- fix: patch release
- breaking changes: major release

Releases should automatically publish artifacts for supported platforms.

Initially prioritize:

- Linux (Fedora)
- iOS

These are the primary testing environments.

## Performance Requirements

Performance is a first-class feature.

Constantly evaluate:

- Memory usage
- CPU usage
- Network usage
- Battery impact
- Database efficiency
- Disk usage
- Binary size
- Cold startup
- Warm startup
- UI responsiveness
- Animation smoothness

The application should not consume excessive resources simply because it resembles Discord.
Likewise, a self-hosted server with only a handful of active users should remain extremely lightweight.
Optimize continuously rather than treating performance as an afterthought.

## Code Quality

Prioritize:

- Proper componentization
- Clean architecture
- Minimal coupling
- High cohesion
- Reusable widgets
- Dependency injection where appropriate
- Comprehensive testing
- Readable APIs
- Clear documentation

Avoid large, difficult-to-maintain files.

## UX Details

Important interaction details include:

- Haptic feedback
- Hover effects
- Smooth animations
- Custom right-click context menus
- High-quality transitions
- Excellent keyboard navigation
- Accessibility

Everything should feel polished.

## Database

Optimize for:

- Efficient lookups
- Efficient indexing
- Low storage overhead
- Fast synchronization
- Future scalability

Avoid premature complexity while still planning for long-term growth.

## Administration

Provide excellent administration tools including:

- User management
- Invite management
- Permissions
- Diagnostics
- Performance metrics
- Logging
- Moderation tools
- Health monitoring

Track performance over time so improvements can be measured objectively.

## Account Model

Official hosted service:

- Standard account creation.

Self-hosted servers:

Ideally users should not need email verification.
Instead, server administrators should be able to invite users through:

- Invite links
- Invite codes

Upon receiving an invite, users should create an account directly on that server.

Evaluate whether this approach conflicts with Apple App Store guidelines and recommend any necessary adjustments.

## Audio Design

Notification sounds are extremely important.

Options include:

- Procedurally generated tones
- Mathematical synthesis
- Python-generated waveforms

Goals:

- Quiet
- Pleasant
- Professional
- Easily distinguishable
- Consistent loudness
- Normalized across operating systems

Each notification should eventually be recognizable purely by sound.
The style should resemble subtle Linux startup/login sounds rather than loud consumer notification effects.

## Deployment

The server must be deployable via Docker.

Requirements:

- Official GHCR image
- Production-ready Dockerfile
- Example docker-compose.yml
- Well-documented deployment process

Deployment should be as simple as possible for self-hosting.

## Overall Goal

Do not optimize for shipping the fastest possible MVP.

Instead, optimize for creating a messaging platform that is:

- Fast
- Lightweight
- Pleasant to use
- Beautifully engineered
- Easy to self-host
- Easy to contribute to
- Sustainable over many years of development

Favor thoughtful architecture, measurable performance, and iterative implementation over rushing features.
