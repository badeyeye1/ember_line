# Emberline screens: the visual spec

The event model (`docs/model.json`) says **what** each screen does. This folder says **how it looks**. Every LiveView
must look like its screen here. A plain Phoenix form that does the right thing is not done.

## What's here

| File | What it is |
|---|---|
| `screens/<screen>.desktop.png` | The screen at 1440 px wide, the full page. Dialogs and drawers are captured at window size. |
| `screens/<screen>.phone.png` | The same screen at 390 px wide. |
| `screens/<screen>.html` | The screen's visible markup from the prototype, with hidden parts removed. Use it for structure, class names and copy. |
| `tokens.css` | Colours, fonts, shadows and the Event Modeling sticky colours, light and dark. |
| `prototype.css` | Every style in the prototype. Look up a class from the markup here. |
| `prototype.html` | The whole prototype. Open it in a browser, sign in with alex@acme.dev / demo1234, and click around. |

The captures show the prototype's sample project (Studio Workshops). Copy the **layout, components, spacing and
wording of labels and buttons**, not the sample data: real data comes from the read models. The product name is
**Emberline**, not "Event-Model Builder".

## How to build a screen

1. Find the slice's `screen` in `docs/model.json`, then open `screens/<screen>.desktop.png`, `.phone.png` and `.html`.
2. Build the shared parts once, as function components in `lib/ember_line_web/components/ui.ex`, and reuse them on every screen:
   - the app shell: sidebar, top bar, breadcrumb, account footer;
   - the auth shell: form on the left, purple panel on the right;
   - buttons, chips and badges, cards, stat tiles, tabs, drawers, dialogs, and sticky notes coloured by element type.
3. Translate the prototype's markup into HEEx using those components and Tailwind classes. Tailwind reads the
   colours from the theme in `assets/css/app.css`, which comes from `tokens.css`.
4. Keep the copy. Headings, labels, button text, help text, empty states and error messages come from the prototype
   and the slice's scenarios.
5. Compare: open the page at 1440 and 390 px wide next to the PNGs. Spacing, alignment, colours, type sizes and
   component shapes should match. Note any difference you leave on purpose in the pull request.

## Screens and their slices

| Screen | Name | Reference | Slices on it |
|---|---|---|---|
| `board` | Board | [board.desktop.png](screens/board.desktop.png) · [phone](screens/board.phone.png) · [markup](screens/board.html) | `view-intake` (state view), `load-prototype` (state change), `split-pages` (state change), `undo-split` (state change), `derive-model` (state change), `create-derived-slices` (automation), `view-board` (state view), `add-slice` (state change), `import-model` (state change), `export-model` (state change), `view-slices` (state view), `add-scenario` (state change) |
| `projects` | Projects | [projects.desktop.png](screens/projects.desktop.png) · [phone](screens/projects.phone.png) · [markup](screens/projects.html) | `view-projects` (state view), `create-project` (state change), `open-sample` (state change) |
| `build` | Build | [build.desktop.png](screens/build.desktop.png) · [phone](screens/build.phone.png) · [markup](screens/build.html) | `view-build` (state view), `send-to-build` (state change), `track-build-progress` (automation) |
| `inbox` | Inbox | [inbox.desktop.png](screens/inbox.desktop.png) · [phone](screens/inbox.phone.png) · [markup](screens/inbox.html) | `deliver-notification` (automation), `view-inbox` (state view), `mark-read` (state change), `mark-all-read` (state change) |
| `account-profile` | Profile | [account-profile.desktop.png](screens/account-profile.desktop.png) · [phone](screens/account-profile.phone.png) · [markup](screens/account-profile.html) | `sign-out` (state change), `view-account` (state view), `save-profile` (state change) |
| `account-security` | Password and security | [account-security.desktop.png](screens/account-security.desktop.png) · [phone](screens/account-security.phone.png) · [markup](screens/account-security.html) | `view-sessions` (state view), `change-password` (state change), `enable-2fa` (state change), `disable-2fa` (state change), `revoke-session` (state change), `revoke-other-sessions` (state change), `connect-signin` (state change), `disconnect-signin` (state change) |
| `account-notifications` | Notifications | [account-notifications.desktop.png](screens/account-notifications.desktop.png) · [phone](screens/account-notifications.phone.png) · [markup](screens/account-notifications.html) | `view-notif-prefs` (state view), `set-notif-pref` (state change) |
| `workspace-general` | Workspace settings | [workspace-general.desktop.png](screens/workspace-general.desktop.png) · [phone](screens/workspace-general.phone.png) · [markup](screens/workspace-general.html) | `view-workspace` (state view), `save-workspace` (state change), `save-domains` (state change), `transfer-owner` (state change), `delete-workspace` (state change), `domain-join` (automation) |
| `workspace-members` | Members | [workspace-members.desktop.png](screens/workspace-members.desktop.png) · [phone](screens/workspace-members.phone.png) · [markup](screens/workspace-members.html) | `view-members` (state view), `invite-members` (state change), `change-role` (state change), `remove-member` (state change), `resend-invite` (state change), `revoke-invite` (state change), `expire-invites` (automation) |
| `workspace-billing` | Plan and billing | [workspace-billing.desktop.png](screens/workspace-billing.desktop.png) · [phone](screens/workspace-billing.phone.png) · [markup](screens/workspace-billing.html) | `view-billing` (state view), `change-plan` (state change), `update-payment` (state change) |
| `workspace-integrations` | Integrations | [workspace-integrations.desktop.png](screens/workspace-integrations.desktop.png) · [phone](screens/workspace-integrations.phone.png) · [markup](screens/workspace-integrations.html) | `view-integrations` (state view), `connect-integration` (state change), `disconnect-integration` (state change), `setup-sso` (state change) |
| `signin` | Sign in | [signin.desktop.png](screens/signin.desktop.png) · [phone](screens/signin.phone.png) · [markup](screens/signin.html) | `view-signin` (state view), `signin` (state change), `oauth-signin` (state change), `view-notfound` (state view) |
| `signup` | Create your account | [signup.desktop.png](screens/signup.desktop.png) · [phone](screens/signup.phone.png) · [markup](screens/signup.html) | `register` (state change) |
| `verify` | Check your email | [verify.desktop.png](screens/verify.desktop.png) · [phone](screens/verify.phone.png) · [markup](screens/verify.html) | `view-verify` (state view), `verify-email` (state change), `resend-code` (state change) |
| `forgot` | Reset your password | [forgot.desktop.png](screens/forgot.desktop.png) · [phone](screens/forgot.phone.png) · [markup](screens/forgot.html) | `request-reset` (state change) |
| `forgot-sent` | Reset link sent | [forgot-sent.desktop.png](screens/forgot-sent.desktop.png) · [phone](screens/forgot-sent.phone.png) · [markup](screens/forgot-sent.html) | `view-reset-sent` (state view) |
| `reset` | Set a new password | [reset.desktop.png](screens/reset.desktop.png) · [phone](screens/reset.phone.png) · [markup](screens/reset.html) | `reset-password` (state change) |
| `sso` | Sign in with SSO | [sso.desktop.png](screens/sso.desktop.png) · [phone](screens/sso.phone.png) · [markup](screens/sso.html) | `sso-signin` (state change) |
| `invite` | Invite | [invite.desktop.png](screens/invite.desktop.png) · [phone](screens/invite.phone.png) · [markup](screens/invite.html) | `view-invite` (state view), `accept-invite` (state change) |
| `welcome` | Welcome | [welcome.desktop.png](screens/welcome.desktop.png) · [phone](screens/welcome.phone.png) · [markup](screens/welcome.html) | `setup-workspace` (state change), `invite-from-welcome` (state change) |
| `slice-page` | Slice page | [slice-page.desktop.png](screens/slice-page.desktop.png) · [phone](screens/slice-page.phone.png) · [markup](screens/slice-page.html) | `view-slice` (state view), `set-status` (state change), `edit-slice` (state change), `move-slice` (state change), `duplicate-slice` (state change), `delete-slice` (state change), `assign-owner` (state change), `unassign-owner` (state change), `request-review` (state change), `approve-spec` (state change), `ask-changes` (state change), `cancel-review` (state change), `reset-review` (state change), `view-review` (state view) |
| `scenario-dialog` | Scenario screenshot dialog | [scenario-dialog.desktop.png](screens/scenario-dialog.desktop.png) · [phone](screens/scenario-dialog.phone.png) · [markup](screens/scenario-dialog.html) | `view-scenario` (state view), `draw-scenario` (state change) |
| `comments` | Discussion drawer | [comments.desktop.png](screens/comments.desktop.png) · [phone](screens/comments.phone.png) · [markup](screens/comments.html) | `view-threads` (state view), `start-thread` (state change), `post-reply` (state change), `resolve-thread` (state change), `reopen-thread` (state change), `dismiss-suggestion` (state change), `add-suggested-scenario` (state change), `resolve-suggestion-thread` (automation) |
| `share` | Share dialog | [share.desktop.png](screens/share.desktop.png) · [phone](screens/share.phone.png) · [markup](screens/share.html) | `view-share` (state view), `share-invite` (state change), `remove-access` (state change) |
