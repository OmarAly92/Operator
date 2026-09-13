import { useQuery } from "@tanstack/react-query";

import {
	fetchMobileStatus,
	mobileStatusQueryKey,
	tunnelIndicatorRefetchInterval,
	type MobileTunnelStatus,
} from "../lib/mobile-status";

export function useMobileTunnelStatus(): MobileTunnelStatus | undefined {
	const query = useQuery({
		queryKey: mobileStatusQueryKey,
		queryFn: fetchMobileStatus,
		refetchInterval: (q) => tunnelIndicatorRefetchInterval(q.state.data?.tunnel?.state),
		retry: false,
	});
	return query.data?.tunnel;
}
