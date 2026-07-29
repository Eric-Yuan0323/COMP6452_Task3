## Tianxiong: Query Interface and Visualization

Tianxiong's part adds a simple executable batch-query interface and a demo visualization.

### Files

- `interface/queryBatch.js` — command-line query by batch ID
- `interface/visualizeDemo.js` — generates an HTML visualization from deployed contract state
- `visualization/demo-dashboard.html` — static demo visualization based on the successful demo output
- `package.json` — adds `query` and `visualize` npm scripts

### Query a batch

```bash
npm install
cp .env.example .env
# Fill in RPC_URL or SEPOLIA_RPC_URL if needed

npm run query -- 1
npm run query -- 2
```

The query displays:

- batch status
- current custodian
- latest temperature
- cold-chain violation status
- recall status

### Generate the visualization from contract state

```bash
npm run visualize -- 1 2
```

This creates:

```text
visualization/batch-dashboard.html
```

Open that HTML file in a browser for the visual demo.

### Static visualization

If the team only needs a presentation screenshot, open:

```text
visualization/demo-dashboard.html
```

This visualizes the existing demo result:

| Batch ID | Scenario | Temperature | Final status | Recalled |
| ---: | --- | ---: | --- | --- |
| 1 | Normal delivery | 4.0°C | Delivered | No |
| 2 | Cold-chain violation | 8.5°C | Recalled | Yes |
```
