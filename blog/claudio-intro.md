# Claudio: why we put our AI agent in a container (and why you should too)

## Why Claudio?

About a year ago, I started using Claude Code. There was just one problem: I'm Italian, and I had no idea how to pronounce "Claude." After a few awkward attempts, I gave up and said what any self-respecting Italian would say: "Whatever. I'm calling it Claudio."

The name stuck. It became a running joke on the team. We created shell aliases (`alias claudio=claude`) and we talked about Claudio like he was a colleague. At one point someone even suggested we rename it to "Claudia" instead — partly because Claude has this tendency to confidently tell you something completely wrong and then act like nothing happened, and we joked about how a woman would never do that to you. (We kept Claudio in the end. He's growing on us.)

But somewhere between the jokes and the aliases, something real started taking shape. Our tech lead saw what we were all experiencing — everyone had a different local setup, prompts were unpredictable, and there was no good way to run any of this unattended — and decided to do something about it. His idea: containerize the whole thing so the environment is consistent for everyone, build a skills system so the agent's behavior is as deterministic as possible (fewer hallucinations, more reliable output), and lean into the agentic flow that just makes sense now for automating.

He called the project Claudio — because by that point, the name had already stuck — and it quickly became a team effort, with several contributors shaping it into what it is today.

## The problem

AI coding assistants are everywhere now. They live in your IDE, your terminal, your browser. They're great at helping you write code. But here's what most of them can't do: run on their own. Wake up at 8 AM on a Monday, check the state of your releases across three different platforms, figure out if something is off, and post a summary to Slack before you've had your coffee. None of the current tools do that.

And honestly, the gap isn't intelligence. The models are smart enough. The problem is that they all assume a human is sitting at the keyboard. Claude Code runs on your laptop, with your tools, your credentials, your environment. That's fine when you're pair programming. But if you want it to triage CI failures overnight, or generate a daily status report, or coordinate a release on a schedule? You need it to run somewhere else. Reproducibly. In isolation. Like any other workload.

So we put it in a container.

## What Claudio actually is

[Claudio](https://github.com/aipcc-cicd/claudio) is an open-source OCI image, built on Red Hat UBI 10, that packages Claude Code with everything it needs to work on its own. Authentication (we use Google Vertex AI), a bunch of DevOps CLI tools — kubectl, glab, skopeo, jq, AWS CLI — and a plugin system called [claudio-skills](https://github.com/aipcc-cicd/claudio-skills) that gives the agent actual capabilities in specific domains.

You can run it locally with `podman run`, deploy it as a Kubernetes CronJob, drop it into a GitLab CI pipeline. Same image everywhere. That's the whole point.

But the container is just packaging. What makes it actually useful is what's inside.

## The skills thing

Here's what I think is the most interesting part. If you've used AI agents for anything serious, you know the biggest problem: reliability. You ask it to "check the release status" and it might hallucinate a kubectl command, or misformat an API call, or just confidently tell you something that isn't true. We've all been there (looking at you, Claudio).

Our answer to this is what we call skills. A skill isn't just a prompt. It's a package with instructions, shell scripts, and Python tools that tell the agent how to work with a specific domain. The idea is simple: we don't trust the AI to write commands on the fly (and you shouldn't either), so we give it pre-written scripts for the parts that matter. The AI is good at figuring out what needs to be done and in what order — but when it's time to actually do it, it calls a script we wrote and tested.

So when Claudio analyzes a GitLab pipeline failure, it's not inventing CLI commands from scratch. It calls a script that retrieves structured data. When it creates a production release, it uses a Python script that generates manifests deterministically. The AI figures out *what* to do. The scripts make sure it's done *correctly*.

This is what makes us comfortable running it unattended. You get the flexibility of an AI agent (it can reason, adapt, handle things you didn't anticipate) without the fragility (because the important stuff is locked down in code that we've tested).

The [claudio-skills repo](https://github.com/aipcc-cicd/claudio-skills) currently has skills for CI/CD analysis, release orchestration, log analysis, Slack, branch management, and Jira. And adding a new one is honestly pretty easy — you create a directory with a markdown file and some scripts. No SDK, no framework. The markdown tells the agent what the skill can do and how to use the scripts. Think of it as a very detailed runbook, except the AI actually follows it (most of the time).

## What we actually do with it

I'll give you a few examples. These are generalized from our actual workflows, because some of the specifics are internal, but you'll get the idea.

You know that feeling when you open Slack in the morning and there are 30 unread messages across five channels, and somewhere in there is the information you need to know whether yesterday's release actually went through? Someone used to spend 30 minutes piecing that together every morning. Now Claudio does it. It runs as a CronJob every weekday morning, queries our release platform, checks relevant Slack channels, and posts a report. But the part I like is that it's not just reformatting data. It actually reasons about what it finds. Is a release blocked? Did someone announce something that hasn't shipped yet? Are there inconsistencies? A static script would miss that stuff, because you can't write rules for inconsistencies you haven't imagined yet.

We also have a dashboard — a web app that tracks the state of our product releases. Leadership cares a lot about how long a release takes. Like, a lot. But we had no reliable way to even say *when* we got the greenlight. There's a team that performs the tests, and when they're done, they post in a Slack channel to say we can start releasing. That message is when the clock starts. The problem? That message could come from anyone, at any time, worded differently every time. You can't write a regex for that. But the information is always roughly the same — there's a version, there's a product, there's an intent — and that's exactly the kind of thing an AI is good at. Claudio reads the Slack channel, recognizes the announcement regardless of who wrote it or how, extracts the relevant data, and records it to the dashboard. A script couldn't do this.

And there's release coordination. Cutting a release across multiple components sounds simple until you actually do it. Check that stage deployments succeeded. Generate manifests. Create branches with the right protection rules. Update tickets. Notify channels. Each step is trivial on its own, but the sequence is where things go wrong. Claudio handles the coordination. The human still reviews and approves — we're not trying to remove judgment from the process — but the toil of assembling everything is gone.

We also just use it interactively. Sometimes I want to ask "why did this pipeline fail?" and get an answer in seconds instead of reading through logs for twenty minutes. That works too.

## But why not just write scripts?

Yeah, fair question. And honestly, if you know exactly what to automate, write a script. It'll be simpler and more predictable.

But a lot of DevOps work doesn't fit neatly into a script. CI triage requires reading logs and forming hypotheses. Checking release status means correlating data from multiple systems. Error analysis needs judgment about what's noise and what actually matters. These things have unpredictable inputs. They need reasoning, not just execution.

I think the sweet spot is tasks that are too complex for a script but too repetitive for a human. You'd be surprised how much of DevOps falls into that category.

## What about lock-in?

Right now, Claudio runs Claude Code. It's literally in the name, we're not hiding it. And the skills system is built around Claude Code's plugin architecture.

But the concept isn't tied to Claude. What makes Claudio useful is the pattern: a containerized AI agent with structured skills, running as a standard OCI workload. The skills themselves are just markdown and shell scripts. They're not coupled to any specific model's API. The container doesn't care what's inside it.

Could we swap the underlying model someday? Support multiple providers? Integrate with a different agent runtime? Yes. The containerization, the skills, the CI/CD integrations — all of that is infrastructure that doesn't depend on which model is running under the hood. We built this to solve an operational problem, not to bet on a single vendor.

For now, Claude Code works well for what we need. If something better comes along, Claudio adapts. That's the nice thing about containers — you can change what's inside without changing how you run them.

## Build on top of it

One thing I want to mention: Claudio is designed as a base image. The open-source project gives you the foundation — the AI runtime, authentication, the plugin system, general-purpose skills. You build your own image on top and add what's specific to your team.

That's exactly what we do. The upstream Claudio image is generic. Our team-specific image adds domain knowledge, access to internal systems, product-specific skills. When the base image improves, every downstream project gets the benefit. When someone builds a useful skill, they can contribute it back.

## Try it

The project is open source under Apache 2.0:

- [Claudio](https://github.com/aipcc-cicd/claudio) — base image, build instructions, wrapper script, CI templates
- [Claudio Skills](https://github.com/aipcc-cicd/claudio-skills) — the skill marketplace with examples and contribution guidelines

If you're spending hours each week on DevOps work that needs judgment — not just execution — it might be worth a look. And if you build something with it, we'd love to hear about it.

Claudio started as a pronunciation joke. He turned out to be a pretty decent colleague. Most days.
