
# Base Query: Decentralized Q&A Platform on Base Chain

## What Is Base Query?

**Base Query** is a decentralized Q&A platform built on **Base** (Coinbase's L2 chain) that leverages smart contracts, USDC rewards, and community governance to create a self-sustaining ecosystem for technical knowledge sharing. Think of it as **Stack Overflow meets Gitcoin** - all running on Base's fast, low-cost infrastructure.

## Technical Architecture

### Smart Contract Layer (Base Chain)
```
Base Query Platform
├── StackExchange.sol (Main Q&A Logic)
├── ReputationSystem.sol (Voting & Reputation)
└── MockUSDC.sol (Test USDC Implementation)
```

### Frontend Integration Layer
```
React/Next.js Frontend
├── Web3 Integration (wagmi, viem)
├── IPFS Content Management (Pinata)
├── Base Chain RPC (Alchemy/Infura)
└── USDC Integration (Circle API)
```

### Data Flow Architecture
```
User Browser ↔ Frontend App ↔ Smart Contracts ↔ Base Chain
                    ↕
               IPFS (Pinata) ↔ Content Storage
```

## Core Smart Contract Functions

### StackExchange Contract
```solidity
// Question Management
function createQuestion(
    string memory ipfsHash, 
    uint256 amount, 
    uint256 poolDuration, 
    bool isPool
) external returns (uint256 questionId);

// Answer Submission
function submitAnswer(
    uint256 questionId, 
    string memory answerIpfsHash
) external returns (uint256 answerId);

// Reward Distribution
function selectBestAnswer(uint256 questionId, uint256 answerId) external;
function distributePool(uint256 questionId) external;
function withdrawPool(uint256 questionId) external;
```

### ReputationSystem Contract
```solidity
// Voting Mechanism
function vote(
    uint256 questionId,
    uint256 contentId,
    ContentType contentType,
    bool isUpvote
) external;

// Reputation Queries
function getUserReputation(address user) external view returns (uint256, uint256);
function canAnswer(address user) external view returns (bool);
function canVote(address user) external view returns (bool);
```

## Frontend Integration Implementation

### 1. Web3 Connection Setup
```typescript
// wagmi configuration for Base
import { createConfig, configureChains } from 'wagmi';
import { baseSepolia } from 'wagmi/chains';
import { publicProvider } from 'wagmi/providers/public';
import { MetaMaskConnector } from 'wagmi/connectors/metaMask';

const { chains, publicClient, webSocketPublicClient } = configureChains(
  [baseSepolia],
  [publicProvider()]
);

export const config = createConfig({
  autoConnect: true,
  connectors: [new MetaMaskConnector({ chains })],
  publicClient,
  webSocketPublicClient,
});
```

### 2. Contract Integration
```typescript
// Contract hooks using wagmi
import { useContractRead, useContractWrite, usePrepareContractWrite } from 'wagmi';
import { STACK_EXCHANGE_ABI, STACK_EXCHANGE_ADDRESS } from '../contracts';

export function useCreateQuestion() {
  const { config } = usePrepareContractWrite({
    address: STACK_EXCHANGE_ADDRESS,
    abi: STACK_EXCHANGE_ABI,
    functionName: 'createQuestion',
  });
  
  return useContractWrite(config);
}

export function useGetQuestion(questionId: number) {
  return useContractRead({
    address: STACK_EXCHANGE_ADDRESS,
    abi: STACK_EXCHANGE_ABI,
    functionName: 'getQuestion',
    args: [questionId],
  });
}
```

### 3. IPFS Content Management
```typescript
// IPFS upload using Pinata
import { create } from '@pinata/sdk';

const pinata = create({
  pinataApiKey: process.env.NEXT_PUBLIC_PINATA_API_KEY!,
  pinataSecretApiKey: process.env.PINATA_SECRET_API_KEY!,
});

export async function uploadToIPFS(content: any) {
  const result = await pinata.pinJSONToIPFS(content);
  return result.IpfsHash;
}

export async function createQuestionContent(
  title: string,
  description: string,
  tags: string[],
  codeSnippets: string[]
) {
  const content = {
    title,
    description,
    tags,
    codeSnippets,
    timestamp: Date.now(),
    version: '1.0.0'
  };
  
  return await uploadToIPFS(content);
}
```

### 4. USDC Integration
```typescript
// USDC approval and transfer
import { parseUnits } from 'viem';
import { USDC_ABI, USDC_ADDRESS } from '../contracts';

export function useUSDCApproval() {
  const { config } = usePrepareContractWrite({
    address: USDC_ADDRESS,
    abi: USDC_ABI,
    functionName: 'approve',
  });
  
  return useContractWrite(config);
}

export async function approveUSDCForQuestion(amount: string) {
  const parsedAmount = parseUnits(amount, 6); // USDC has 6 decimals
  
  // First approve USDC spending
  await approveUSDC({
    args: [STACK_EXCHANGE_ADDRESS, parsedAmount],
  });
  
  // Then create question
  await createQuestion({
    args: [ipfsHash, parsedAmount, 0, false],
  });
}
```

## Complete User Flow Implementation

### Phase 1: Question Creation (Frontend + Smart Contract)

```typescript
// React component for question creation
export function CreateQuestionForm() {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [bounty, setBounty] = useState('');
  const [isPool, setIsPool] = useState(false);
  const [poolDuration, setPoolDuration] = useState(86400); // 24 hours
  
  const { write: createQuestion, isLoading } = useCreateQuestion();
  const { write: approveUSDC } = useUSDCApproval();
  
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    try {
      // 1. Upload content to IPFS
      const content = await createQuestionContent(title, description, [], []);
      
      // 2. Approve USDC spending
      const amount = parseUnits(bounty, 6);
      await approveUSDC({ args: [STACK_EXCHANGE_ADDRESS, amount] });
      
      // 3. Create question on-chain
      await createQuestion({
        args: [content, amount, isPool ? poolDuration : 0, isPool],
      });
      
      // 4. Update UI state
      toast.success('Question created successfully!');
      
    } catch (error) {
      console.error('Error creating question:', error);
      toast.error('Failed to create question');
    }
  };
  
  return (
    <form onSubmit={handleSubmit}>
      <input
        type="text"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="Question title"
        required
      />
      
      <textarea
        value={description}
        onChange={(e) => setDescription(e.target.value)}
        placeholder="Describe your problem..."
        required
      />
      
      <input
        type="number"
        value={bounty}
        onChange={(e) => setBounty(e.target.value)}
        placeholder="USDC bounty amount"
        min="0.01"
        step="0.01"
        required
      />
      
      <label>
        <input
          type="checkbox"
          checked={isPool}
          onChange={(e) => setIsPool(e.target.checked)}
        />
        Prize Pool Question
      </label>
      
      {isPool && (
        <select
          value={poolDuration}
          onChange={(e) => setPoolDuration(Number(e.target.value))}
        >
          <option value={3600}>1 hour</option>
          <option value={86400}>24 hours</option>
          <option value={604800}>1 week</option>
        </select>
      )}
      
      <button type="submit" disabled={isLoading}>
        {isLoading ? 'Creating...' : 'Create Question'}
      </button>
    </form>
  );
}
```

### Phase 2: Answer Submission

```typescript
export function AnswerForm({ questionId }: { questionId: number }) {
  const [answer, setAnswer] = useState('');
  const { write: submitAnswer, isLoading } = useSubmitAnswer();
  
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    try {
      // 1. Upload answer to IPFS
      const answerContent = await uploadToIPFS({
        content: answer,
        timestamp: Date.now(),
        questionId
      });
      
      // 2. Submit answer on-chain
      await submitAnswer({
        args: [questionId, answerContent],
      });
      
      toast.success('Answer submitted successfully!');
      setAnswer('');
      
    } catch (error) {
      console.error('Error submitting answer:', error);
      toast.error('Failed to submit answer');
    }
  };
  
  return (
    <form onSubmit={handleSubmit}>
      <textarea
        value={answer}
        onChange={(e) => setAnswer(e.target.value)}
        placeholder="Write your answer..."
        required
      />
      <button type="submit" disabled={isLoading}>
        {isLoading ? 'Submitting...' : 'Submit Answer'}
      </button>
    </form>
  );
}
```

### Phase 3: Voting System

```typescript
export function VoteButtons({ 
  questionId, 
  answerId, 
  contentType 
}: { 
  questionId: number; 
  answerId: number; 
  contentType: 'QUESTION' | 'ANSWER' 
}) {
  const { write: vote, isLoading } = useVote();
  
  const handleVote = async (isUpvote: boolean) => {
    try {
      await vote({
        args: [questionId, answerId, contentType === 'ANSWER' ? 1 : 0, isUpvote],
      });
      
      toast.success(`Vote ${isUpvote ? 'upvoted' : 'downvoted'} successfully!`);
      
    } catch (error) {
      console.error('Error voting:', error);
      toast.error('Failed to vote');
    }
  };
  
  return (
    <div className="vote-buttons">
      <button
        onClick={() => handleVote(true)}
        disabled={isLoading}
        className="vote-up"
      >
        ▲ Upvote
      </button>
      
      <button
        onClick={() => handleVote(false)}
        disabled={isLoading}
        className="vote-down"
      >
        ▼ Downvote
      </button>
    </div>
  );
}
```

### Phase 4: Reward Distribution

```typescript
export function RewardDistribution({ questionId }: { questionId: number }) {
  const { data: question } = useGetQuestion(questionId);
  const { write: selectBestAnswer } = useSelectBestAnswer();
  const { write: distributePool } = useDistributePool();
  const { write: withdrawPool } = useWithdrawPool();
  
  const handleSelectBestAnswer = async (answerId: number) => {
    try {
      await selectBestAnswer({ args: [questionId, answerId] });
      toast.success('Best answer selected!');
    } catch (error) {
      toast.error('Failed to select best answer');
    }
  };
  
  const handleDistributePool = async () => {
    try {
      await distributePool({ args: [questionId] });
      toast.success('Pool distributed successfully!');
    } catch (error) {
      toast.error('Failed to distribute pool');
    }
  };
  
  const handleWithdrawPool = async () => {
    try {
      await withdrawPool({ args: [questionId] });
      toast.success('Pool withdrawn successfully!');
    } catch (error) {
      toast.error('Failed to withdraw pool');
    }
  };
  
  if (question?.isPoolQuestion) {
    return (
      <div className="pool-actions">
        {question.poolExpired && !question.poolDistributed && (
          <button onClick={handleDistributePool}>
            Distribute Pool
          </button>
        )}
        
        {question.poolExpired && !question.poolDistributed && (
          <button onClick={handleWithdrawPool}>
            Withdraw Pool
          </button>
        )}
      </div>
    );
  }
  
  return (
    <div className="bounty-actions">
      {/* Render answer selection UI */}
    </div>
  );
}
```

## Base Chain Integration Details

### Network Configuration
```typescript
// Base Sepolia Testnet Configuration
export const BASE_SEPOLIA_CONFIG = {
  chainId: 84532,
  name: 'Base Sepolia',
  nativeCurrency: {
    name: 'ETH',
    symbol: 'ETH',
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: ['https://sepolia.base.org'],
    },
    public: {
      http: ['https://sepolia.base.org'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Base Sepolia Explorer',
      url: 'https://sepolia.basescan.org',
    },
  },
} as const;
```

### Gas Optimization
```typescript
// Gas estimation for Base chain
export function useGasEstimation() {
  const { data: gasPrice } = useGasPrice();
  const { data: block } = useBlock();
  
  const estimateGas = useCallback(async (transaction: any) => {
    try {
      const gasEstimate = await publicClient.estimateGas({
        account: address,
        ...transaction,
      });
      
      // Base chain typically has lower gas costs
      // Add 20% buffer for safety
      return gasEstimate * 120n / 100n;
      
    } catch (error) {
      console.error('Gas estimation failed:', error);
      return 500000n; // Fallback gas limit
    }
  }, [address, publicClient]);
  
  return { estimateGas, gasPrice, block };
}
```

### USDC on Base
```typescript
// USDC contract addresses on Base
export const USDC_ADDRESSES = {
  baseSepolia: 'BASE_SEPOLIA_USDC=0x036CbD53842c5426634e7929541eC2318f3dCF7e
8', // Testnet
  baseMainnet: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', // Mainnet
} as const;

// USDC balance checking
export function useUSDCBalance(address?: string) {
  return useBalance({
    address: address as `0x${string}`,
    token: USDC_ADDRESSES.baseSepolia,
    watch: true,
  });
}
```

## Real-Time Updates & State Management

### WebSocket Integration for Live Updates
```typescript
// Real-time question updates
export function useQuestionUpdates(questionId: number) {
  const [question, setQuestion] = useState<Question | null>(null);
  
  useEffect(() => {
    // Listen for contract events
    const unwatch = publicClient.watchContractEvent({
      address: STACK_EXCHANGE_ADDRESS,
      abi: STACK_EXCHANGE_ABI,
      eventName: 'QuestionCreated',
      onLogs: (logs) => {
        // Update local state
        setQuestion(prev => ({ ...prev, ...logs[0].args }));
      },
    });
    
    return () => unwatch();
  }, [questionId, publicClient]);
  
  return question;
}
```

### Optimistic Updates
```typesity
// Optimistic UI updates for better UX
export function useOptimisticVote() {
  const queryClient = useQueryClient();
  
  const optimisticVote = useCallback(async (
    questionId: number,
    answerId: number,
    isUpvote: boolean
  ) => {
    // Optimistically update UI
    queryClient.setQueryData(
      ['question', questionId],
      (old: any) => ({
        ...old,
        answers: old.answers.map((answer: any) =>
          answer.id === answerId
            ? {
                ...answer,
                upvotes: isUpvote 
                  ? answer.upvotes + 1 
                  : answer.upvotes,
                downvotes: !isUpvote 
                  ? answer.downvotes + 1 
                  : answer.downvotes,
              }
            : answer
        ),
      })
    );
    
    // Perform actual vote
    await vote({ args: [questionId, answerId, 1, isUpvote] });
    
    // Refetch to sync with blockchain
    queryClient.invalidateQueries(['question', questionId]);
  }, [queryClient, vote]);
  
  return { optimisticVote };
}
```

## Deployment & Testing

### Local Development
```bash
# Start local Anvil instance
anvil --port 8545

# Deploy contracts locally
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Run tests
forge test --match-test test_PoolQuestionUSDCFlow -vv
```

### Base Sepolia Testnet
```bash
# Deploy to Base Sepolia
forge script script/Deploy.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

### Frontend Environment
```env
# .env.local
NEXT_PUBLIC_BASE_SEPOLIA_RPC=https://sepolia.base.org
NEXT_PUBLIC_STACK_EXCHANGE_ADDRESS=0x...
NEXT_PUBLIC_REPUTATION_SYSTEM_ADDRESS=0x...
NEXT_PUBLIC_USDC_ADDRESS=BASE_SEPOLIA_USDC=0x036CbD53842c5426634e7929541eC2318f3dCF7e
8
NEXT_PUBLIC_PINATA_API_KEY=your_pinata_key
```

## The Bottom Line

**Base Query** represents the future of decentralized knowledge sharing - combining the reliability of Base chain, the efficiency of smart contracts, and the power of community governance. By building on Base, we get:

- **Low gas costs** for frequent interactions
- **Fast finality** for real-time updates
- **Ethereum security** through optimistic rollups
- **USDC integration** for seamless payments
- **Developer-friendly** tooling and documentation

The platform creates a self-sustaining ecosystem where quality content is automatically rewarded, spam is prevented through economic incentives, and the community drives continuous improvement through reputation-based governance.