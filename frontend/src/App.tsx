import { useStream } from "@langchain/langgraph-sdk/react";
import type { Message } from "@langchain/langgraph-sdk";
import { useState, useEffect, useRef, useCallback } from "react";
import { ProcessedEvent } from "@/components/ActivityTimeline";
import { WelcomeScreen } from "@/components/WelcomeScreen";
import { ChatMessagesView } from "@/components/ChatMessagesView";

export default function App() {
  const [processedEventsTimeline, setProcessedEventsTimeline] = useState<
    ProcessedEvent[]
  >([]);
  const [historicalActivities, setHistoricalActivities] = useState<
    Record<string, ProcessedEvent[]>
  >({});
  const [debugEvents, setDebugEvents] = useState<any[]>([]);
  const [showDebug, setShowDebug] = useState(true);
  const scrollAreaRef = useRef<HTMLDivElement>(null);
  const hasFinalizeEventOccurredRef = useRef(false);

  const thread = useStream<{
    messages: Message[];
    initial_search_query_count: number;
    max_research_loops: number;
    reasoning_model: string;
  }>({
    apiUrl: import.meta.env.DEV
      ? "http://localhost:2024"
      : "http://localhost:8123",
    assistantId: "agent",
    messagesKey: "messages",
    onFinish: (event: any) => {
      console.log("Stream finished:", event);
      setDebugEvents(prev => [...prev, { type: 'onFinish', event, timestamp: new Date().toISOString() }]);
    },
    onError: (error: any) => {
      console.error("Stream error:", error);
      setDebugEvents(prev => [...prev, { type: 'onError', error, timestamp: new Date().toISOString() }]);
    },
    onUpdateEvent: (event: any) => {
      console.log("Received event:", event);
      setDebugEvents(prev => [...prev, { type: 'onUpdateEvent', event, timestamp: new Date().toISOString() }]);
      let processedEvent: ProcessedEvent | null = null;
      
      // Handle different event types based on LangGraph node names
      if (event.event === "on_chain_start" || event.event === "on_chain_stream") {
        const metadata = event.metadata || {};
        const data = event.data || {};
        
        // Handle node-specific events
        if (metadata.langgraph_node === "generate_query" && data.output) {
          processedEvent = {
            title: "Generating Search Queries",
            data: Array.isArray(data.output.query_list) 
              ? data.output.query_list.join(", ")
              : "Generating search queries...",
          };
        } else if (metadata.langgraph_node === "web_research" && data.output) {
          const sources = data.output.sources_gathered || [];
          const numSources = sources.length;
          const uniqueLabels = [
            ...new Set(sources.map((s: any) => s.label).filter(Boolean)),
          ];
          const exampleLabels = uniqueLabels.slice(0, 3).join(", ");
          processedEvent = {
            title: "Web Research",
            data: `Gathered ${numSources} sources. Related to: ${
              exampleLabels || "N/A"
            }.`,
          };
        } else if (metadata.langgraph_node === "reflection" && data.output) {
          processedEvent = {
            title: "Reflection",
            data: data.output.is_sufficient
              ? "Search successful, generating final answer."
              : `Need more information, searching for ${(data.output.follow_up_queries || []).join(
                  ", "
                )}`,
          };
        } else if (metadata.langgraph_node === "finalize_answer") {
          processedEvent = {
            title: "Finalizing Answer",
            data: "Composing and presenting the final answer.",
          };
          hasFinalizeEventOccurredRef.current = true;
        }
      }
      
      // Fallback for legacy event format
      if (!processedEvent) {
        if (event.generate_query) {
          processedEvent = {
            title: "Generating Search Queries",
            data: event.generate_query.query_list?.join(", ") || "Generating search queries...",
          };
        } else if (event.web_research) {
          const sources = event.web_research.sources_gathered || [];
          const numSources = sources.length;
          const uniqueLabels = [
            ...new Set(sources.map((s: any) => s.label).filter(Boolean)),
          ];
          const exampleLabels = uniqueLabels.slice(0, 3).join(", ");
          processedEvent = {
            title: "Web Research",
            data: `Gathered ${numSources} sources. Related to: ${
              exampleLabels || "N/A"
            }.`,
          };
        } else if (event.reflection) {
          processedEvent = {
            title: "Reflection",
            data: event.reflection.is_sufficient
              ? "Search successful, generating final answer."
              : `Need more information, searching for ${(event.reflection.follow_up_queries || []).join(
                  ", "
                )}`,
          };
        } else if (event.finalize_answer) {
          processedEvent = {
            title: "Finalizing Answer",
            data: "Composing and presenting the final answer.",
          };
          hasFinalizeEventOccurredRef.current = true;
        }
      }
      
      if (processedEvent) {
        console.log("Adding processed event:", processedEvent);
        setProcessedEventsTimeline((prevEvents) => [
          ...prevEvents,
          processedEvent!,
        ]);
      }
    },
  });

  useEffect(() => {
    if (scrollAreaRef.current) {
      const scrollViewport = scrollAreaRef.current.querySelector(
        "[data-radix-scroll-area-viewport]"
      );
      if (scrollViewport) {
        scrollViewport.scrollTop = scrollViewport.scrollHeight;
      }
    }
  }, [thread.messages]);

  useEffect(() => {
    if (
      hasFinalizeEventOccurredRef.current &&
      !thread.isLoading &&
      thread.messages.length > 0
    ) {
      const lastMessage = thread.messages[thread.messages.length - 1];
      if (lastMessage && lastMessage.type === "ai" && lastMessage.id) {
        setHistoricalActivities((prev) => ({
          ...prev,
          [lastMessage.id!]: [...processedEventsTimeline],
        }));
        // Clear the live timeline now that it's saved to history
        setProcessedEventsTimeline([]);
      }
      hasFinalizeEventOccurredRef.current = false;
    }
  }, [thread.messages, thread.isLoading, processedEventsTimeline]);

  // Debug logging
  useEffect(() => {
    console.log("Current state:", {
      isLoading: thread.isLoading,
      eventsCount: processedEventsTimeline.length,
      events: processedEventsTimeline,
    });
  }, [thread.isLoading, processedEventsTimeline]);

  const handleSubmit = useCallback(
    (submittedInputValue: string, effort: string, model: string) => {
      if (!submittedInputValue.trim()) return;
      setProcessedEventsTimeline([]);
      setDebugEvents([]);
      hasFinalizeEventOccurredRef.current = false;

      // convert effort to, initial_search_query_count and max_research_loops
      // low means max 1 loop and 1 query
      // medium means max 3 loops and 3 queries
      // high means max 10 loops and 5 queries
      let initial_search_query_count = 0;
      let max_research_loops = 0;
      switch (effort) {
        case "low":
          initial_search_query_count = 1;
          max_research_loops = 1;
          break;
        case "medium":
          initial_search_query_count = 3;
          max_research_loops = 3;
          break;
        case "high":
          initial_search_query_count = 5;
          max_research_loops = 10;
          break;
      }

      const newMessages: Message[] = [
        ...(thread.messages || []),
        {
          type: "human",
          content: submittedInputValue,
          id: Date.now().toString(),
        },
      ];
      thread.submit({
        messages: newMessages,
        initial_search_query_count: initial_search_query_count,
        max_research_loops: max_research_loops,
        reasoning_model: model,
      });
    },
    [thread]
  );

  const handleCancel = useCallback(() => {
    thread.stop();
    window.location.reload();
  }, [thread]);

  return (
    <div className="flex h-screen bg-neutral-800 text-neutral-100 font-sans antialiased">
      <main className="flex-1 flex flex-col overflow-hidden max-w-4xl mx-auto w-full">
        <div
          className={`flex-1 overflow-y-auto ${
            thread.messages.length === 0 ? "flex" : ""
          }`}
        >
          {thread.messages.length === 0 ? (
            <WelcomeScreen
              handleSubmit={handleSubmit}
              isLoading={thread.isLoading}
              onCancel={handleCancel}
            />
          ) : (
            <ChatMessagesView
              messages={thread.messages}
              isLoading={thread.isLoading}
              scrollAreaRef={scrollAreaRef}
              onSubmit={handleSubmit}
              onCancel={handleCancel}
              liveActivityEvents={processedEventsTimeline}
              historicalActivities={historicalActivities}
            />
          )}
        </div>
      </main>
      
      {/* Debug Panel */}
      {showDebug && (
        <div className="fixed bottom-0 right-0 w-96 h-96 bg-neutral-900 border border-neutral-700 rounded-tl-lg overflow-hidden flex flex-col">
          <div className="p-2 bg-neutral-800 flex justify-between items-center">
            <span className="text-xs font-mono">Debug Panel</span>
            <button 
              onClick={() => setShowDebug(false)}
              className="text-xs hover:text-neutral-400"
            >
              Close
            </button>
          </div>
          <div className="flex-1 overflow-y-auto p-2 text-xs font-mono">
            <div className="mb-2 text-yellow-400">
              Timeline Events: {processedEventsTimeline.length}
            </div>
            <div className="mb-2 text-green-400">
              Loading: {thread.isLoading ? 'true' : 'false'}
            </div>
            <div className="border-t border-neutral-700 mt-2 pt-2">
              <div className="text-blue-400 mb-1">Raw Events:</div>
              {debugEvents.map((item, index) => (
                <div key={index} className="mb-2 border-b border-neutral-800 pb-1">
                  <div className="text-yellow-300">{item.type} @ {item.timestamp}</div>
                  <pre className="text-[10px] overflow-x-auto">
                    {JSON.stringify(item.event || item.error, null, 2)}
                  </pre>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
      {!showDebug && (
        <button 
          onClick={() => setShowDebug(true)}
          className="fixed bottom-4 right-4 bg-neutral-700 hover:bg-neutral-600 px-3 py-1 rounded text-xs"
        >
          Show Debug
        </button>
      )}
    </div>
  );
}
