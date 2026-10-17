# 单文件交互交付物（Artifact）

当交付物必须是**一个自包含 HTML**（React + TypeScript + Vite + Tailwind + 本地 shadcn/ui，经 `vite-plugin-singlefile` 打成 `bundle.html`）时读本篇。剧本、看板、原型、演示工具都属于这一类；常规前端项目改动不要走这条路径。

Build standalone artifacts using React, TypeScript, Vite, Tailwind CSS, and local shadcn/ui components, producing a self-contained `bundle.html` via `vite-plugin-singlefile`.

## Workflow

1. Clarify the target user, core workflow, data/states that must be displayed, and the single-file constraint.
2. Run the initialization script from the Web skill directory (`~/.agents/skills/web-ui-design`):

   ```bash
   bash ~/.agents/skills/web-ui-design/scripts/init-artifact.sh <project-name>
   ```

3. Implement the actual experience in the generated project. Prefer reusing installed components; don't replace information architecture with decorative cards, gradients, or hero sections.
4. Run the project's typecheck/build and start the preview server.
5. Use the playwright MCP to test desktop and mobile main flows, keyboard focus, empty/error/loading states, and console checks; use visual/image review tools only when visual semantics require judgment.
6. Switch to the project root and bundle:

   ```bash
   bash ~/.agents/skills/web-ui-design/scripts/bundle-artifact.sh
   ```

7. Re-open `bundle.html` and verify. Don't assume the dev server working means the inlined artifact works.

## Artifact Constraints

- First screen goes directly into the tool or content; no marketing hero.
- Data-driven repetition; avoid duplicating views and event handlers.
- Controls use stable sizes with clear states; longest text, narrow viewports, and dynamic content must not cause overflow or layout jumps.
- Use semantic HTML, visible focus, label/aria, and keyboard operation; color is not the only state indicator.
- Delivered file must not depend on local absolute paths, dev server, or uninlined private resources.
- No placeholder copy, fake buttons, unreachable views, or console errors.

## Completion Criteria

- `npm run build`/project checks pass.
- Desktop and mobile main flows have been tested hands-on.
- `bundle.html` opens independently with key resources, interactions, and content intact.
- Provide the absolute path of the final artifact; if the preview server is still running, provide the URL as well.
