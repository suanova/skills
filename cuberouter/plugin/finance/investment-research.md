# Investment Research Skill (AI Berkshire Methodology + Finance MCP)

## Purpose

This skill reproduces the investment research methodology inspired by Buffett, Munger, Duan Yongping, and Li Lu.

The goal is not to predict stock prices.

The goal is to understand:

-   What business is this?
-   Is it a great business?
-   Does it have a durable competitive advantage?
-   Is management trustworthy and rational?
-   Is the current price reasonable compared with intrinsic value?

All factual financial data MUST be obtained through Finance MCP tools.

The skill is responsible for:

-   research methodology
-   reasoning framework
-   investment analysis
-   report generation

MCP is responsible for:

-   financial data
-   market data
-   company information
-   news/events

------------------------------------------------------------------------

# Research Workflow

The research MUST follow the sequence below.

# Step 0: AI Research Bias Awareness (Mandatory)

Before starting analysis, evaluate the limitations of AI research.

## 0.1 AI Researchability Assessment

Evaluate:

### Data Availability

Check:

-   Are financial statements available?
-   Are historical financial records complete?
-   Are company disclosures sufficient?
-   Are industry data available?

Output:

    Researchability Score: 0-5

    Reason:

------------------------------------------------------------------------

## 0.2 Data Bias Identification

Identify possible biases.

### Survivorship Bias

Question:

Is the company successful because of real business quality, or are we only observing a surviving company?

### Financial Statement Bias

Check:

-   revenue recognition issues
-   unusual accounting treatment
-   one-time profits
-   capitalized expenses

### Narrative Bias

Check whether judgement is influenced by:

-   famous founder
-   hot industry
-   market popularity
-   short-term news

### Market Price Bias

Avoid:

-   assuming high stock price means good company
-   assuming low PE means cheap

------------------------------------------------------------------------

## 0.3 AI Capability Boundary

Clearly separate:

AI can analyze:

-   financial statements
-   historical performance
-   business model
-   competitive landscape
-   valuation scenarios

AI cannot reliably know:

-   management integrity
-   hidden company information
-   future technological disruption
-   real customer loyalty

------------------------------------------------------------------------

## 0.4 Confidence Level

Output:

    Research Confidence:

    High / Medium / Low

    Reason:

------------------------------------------------------------------------

# Step 1: Company Understanding

Goal:

Understand the business before analyzing numbers.

Use MCP:

    get_company_profile(symbol)

Analyze:

## Business Model

Answer:

-   What does the company sell?
-   Who are the customers?
-   How does it make money?
-   Why do customers choose it?

## Business Simplicity

Buffett principle:

Only analyze businesses that can be understood.

Evaluate:

-   Is the business easy to explain?
-   Are revenue sources clear?

Output:

## Company Summary

------------------------------------------------------------------------

# Step 2: Business Quality Analysis

Analyze the company from a long-term owner perspective.

## Industry Position

Evaluate:

-   industry growth
-   competitive landscape
-   industry economics

## Business Characteristics

Analyze:

-   recurring revenue
-   pricing power
-   customer dependence
-   scalability

Output:

## Business Quality Assessment

------------------------------------------------------------------------

# Step 3: Competitive Advantage (Moat)

Analyze according to Buffett/Munger framework.

## Brand Advantage

Questions:

-   Does the company have customer trust?
-   Can it charge premium prices?

## Network Effect

Questions:

-   Does the product become stronger with more users?

## Switching Cost

Questions:

-   Is leaving the company expensive or inconvenient?

## Cost Advantage

Questions:

-   Does the company have structural cost advantages?

## Intangible Assets

Evaluate:

-   patents
-   licenses
-   reputation
-   ecosystem

Output:

    Moat Score: 0-5

    Strong / Moderate / Weak

    Reason:

------------------------------------------------------------------------

# Step 4: Financial Analysis

Use Finance MCP:

    get_financial_statement(symbol, statement_type, years)

    get_financial_metrics(symbol, years)

Analyze:

## Growth

Evaluate:

-   revenue CAGR
-   earnings growth
-   growth stability

## Profitability

Evaluate:

-   gross margin
-   operating margin
-   ROE
-   ROIC

## Cash Flow Quality

Evaluate:

-   operating cash flow
-   free cash flow
-   earnings conversion

## Balance Sheet Safety

Evaluate:

-   debt level
-   cash position
-   financial resilience

Questions:

-   Does the company create economic value?
-   Are profits converted into cash?

------------------------------------------------------------------------

# Step 5: Management Analysis

Evaluate management quality.

Analyze:

## Capital Allocation

Questions:

-   Are acquisitions rational?
-   Are investments generating returns?

## Shareholder Orientation

Questions:

-   Does management treat shareholders fairly?
-   Is dilution controlled?

## Long-Term Thinking

Questions:

-   Does management focus on sustainable value creation?

Output:

## Management Assessment

------------------------------------------------------------------------

# Step 6: Valuation Analysis

Use MCP:

    get_stock_quote(symbol)

    get_financial_metrics(symbol)

Analyze:

## Current Valuation

Evaluate:

-   PE
-   PB
-   market capitalization
-   historical valuation range

## Intrinsic Value

Estimate:

-   owner earnings
-   reasonable growth assumptions
-   reasonable valuation multiple

Do NOT provide false precision.

Use:

    Bear Case

    Base Case

    Bull Case

Output:

## Valuation Assessment

------------------------------------------------------------------------

# Step 7: Risk Analysis

Analyze:

## Business Risks

Examples:

-   industry decline
-   competition
-   technology change

## Financial Risks

Examples:

-   excessive debt
-   weak cash flow

## Management Risks

Examples:

-   poor capital allocation
-   governance issues

## Valuation Risks

Examples:

-   excessive expectations

Output:

## Risk Assessment

------------------------------------------------------------------------

# Final Investment Report

Generate:

# Investment Research Report

## 1. AI Research Bias Assessment

-   Researchability Score
-   Data limitations
-   Confidence level

## 2. Company Overview

## 3. Business Quality

## 4. Competitive Advantage

## 5. Financial Analysis

## 6. Management Evaluation

## 7. Valuation

## 8. Risks

## 9. Investment Thesis

------------------------------------------------------------------------

# Final Decision

Choose one:

## Attractive

Strong business quality + reasonable valuation.

## Watchlist

Good business but valuation or uncertainty needs monitoring.

## Avoid

Weak business quality, poor economics, or excessive risks.

Explain the reasoning.

------------------------------------------------------------------------

# Rules

1.  Never fabricate financial data.
2.  Always distinguish facts from opinions.
3.  Use MCP for all financial facts.
4.  Do not make short-term trading predictions.
5.  Focus on long-term business ownership.
6.  If information is insufficient, explicitly state uncertainty.
