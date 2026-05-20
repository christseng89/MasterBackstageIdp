**Backstage Catalog** (also called the Software Catalog) is one of the core features of [Backstage](https://backstage.io), the open-source developer portal framework created by Spotify.

Here's what it is and what it does:

**What it is:** A centralized registry of all the software assets (services, libraries, websites, pipelines, etc.) in your organization. Think of it as a "yellow pages" or an inventory system for your entire software ecosystem.

**What it tracks:** The Catalog organizes entities into different kinds, such as:
- **Components** – microservices, libraries, websites, data pipelines
- **APIs** – the interfaces components expose or consume
- **Systems** – a collection of related components
- **Domains** – groups of systems aligned to a business area
- **Resources** – physical or virtual infrastructure (databases, S3 buckets, etc.)
- **Users & Groups** – people and teams in your organization

**How it works:** You define entities using **YAML descriptor files** (usually called `catalog-info.yaml`) that live alongside your code in source control (e.g., GitHub). Backstage reads these files and ingests them into the catalog, keeping everything in sync automatically.

**Key benefits:**
- **Discoverability** – engineers can easily find services, their owners, documentation, and dependencies
- **Ownership clarity** – every component has a designated team/owner, reducing the "who owns this?" problem
- **Dependency mapping** – you can visualize relationships between components, APIs, and systems
- **Single source of truth** – all metadata about your software lives in one place, reducing tribal knowledge

**In the context of Platform Engineering**, the Backstage Catalog is the foundation on top of which other capabilities (like scaffolding new services, TechDocs, and plugins) are built. It answers the fundamental question: *"What software do we have, who owns it, and how does it all fit together?"*
