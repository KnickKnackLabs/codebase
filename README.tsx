/** @jsxImportSource jsx-md */

import { execFileSync } from "node:child_process";
import { Badge, Badges, Center, Code, CodeBlock, Heading, Link, Paragraph, Raw, Section } from "readme";

// The public task excludes intentionally invalid fixtures from its test inventory.
const testCount = execFileSync("mise", ["run", "test", "--count"], {
  cwd: import.meta.dirname,
  encoding: "utf8",
}).trim();
if (!/^\d+$/.test(testCount)) throw new Error("Expected the maintained BATS test count");

console.log(
  <>
    <Center>
      <Raw>{`<img src="assets/logo.jpg" alt="Pink and lime open-book emblem with a quill, torch, and EDUKASHUN lettering" width="800">\n\n`}</Raw>
      <Heading level={1}>codebase</Heading>
      <Badges>
        <Badge label="tests" value={testCount} color="brightgreen" href="test/" />
        <Badge label="license" value="MIT" color="blue" href="LICENSE" />
      </Badges>
    </Center>

    <Paragraph>
      Repository conventions, written down and checked. Codebase runs the rules
      declared in <Code>mise.toml</Code> against Bash, mise tasks, BATS tests,
      and GitHub Actions. Pick individual rules or groups, then run one command.
    </Paragraph>

    <Section title="Install">
      <CodeBlock lang="bash">shiv install codebase</CodeBlock>
      <Paragraph>Or declare it for a project in <Code>mise.toml</Code>:</Paragraph>
      <CodeBlock lang="toml">{`[plugins]
shiv = "https://github.com/KnickKnackLabs/vfox-shiv"

[tools]
"shiv:codebase" = "0.5"`}</CodeBlock>
      <CodeBlock lang="bash">mise install</CodeBlock>
    </Section>

    <Section title="Run">
      <Paragraph>Choose the conventions for your repository in <Code>mise.toml</Code>:</Paragraph>
      <CodeBlock lang="toml">{`[_.codebase]
name = "my-tool"
lint = ["@shell", "@mise"]`}</CodeBlock>
      <CodeBlock lang="bash">{`codebase lint .          # run the configured rules
codebase lint:groups     # inspect available groups and their members
codebase pre-commit      # optionally install a clone-local lint hook`}</CodeBlock>
      <Paragraph>Group membership evolves when you upgrade Codebase.</Paragraph>
    </Section>

    <Section title="Documentation">
      <Paragraph>
        Commands include examples in <Code>--help</Code>. See
        {" "}<Link href="docs/ci-lint-enforcement.md">CI lint enforcement</Link>
        {" "}for direct lint steps and the explicitly trusted aggregate-gate option
        introduced in Codebase 0.5.
      </Paragraph>
      <Paragraph>
        From a prepared source checkout, <Code>mise run test</Code> runs the suite.
        Edit <Code>README.tsx</Code> and run <Code>readme build</Code> to update this page.
      </Paragraph>
    </Section>
  </>,
);
