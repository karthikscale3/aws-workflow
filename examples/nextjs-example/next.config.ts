import type { NextConfig } from "next";
import { withWorkflow } from "workflow/next";

const nextConfig: NextConfig = {
  experimental: {
    // @ts-expect-error - instrumentationHook exists but not in types
    instrumentationHook: true,
  },
};

export default withWorkflow(nextConfig);
