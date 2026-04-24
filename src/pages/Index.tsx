import { useEffect } from "react";

const Index = () => {
  useEffect(() => {
    window.location.replace("/flowdesk.html");
  }, []);
  return (
    <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center", background: "#0f0f13", color: "#e8e8f0", fontFamily: "system-ui, sans-serif" }}>
      Loading FlowDesk…
    </div>
  );
};

export default Index;
