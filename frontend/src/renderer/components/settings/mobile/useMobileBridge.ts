import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import type { UseQueryResult } from "@tanstack/react-query";

import { apiClient, apiErrorMessage } from "../../../lib/api-client";
import { captureRendererEvent } from "../../../lib/telemetry";
import {
	fetchMobileStatus,
	mobileStatusQueryKey,
	tunnelRefetchInterval,
	type MobileStatus,
	type MobileTunnelStatus,
} from "../../../lib/mobile-status";
import { tunnelAlreadyConfirmed } from "../../../lib/tunnel-confirm";

export interface MobileBridge {
	query: UseQueryResult<MobileStatus>;
	status: MobileStatus | undefined;
	enabled: boolean;
	busy: boolean;
	tunnel: MobileTunnelStatus | undefined;
	tunnelLive: boolean;
	tunnelOn: boolean;
	tunnelBusy: boolean;
	address: string | undefined;
	actionError: string | null;
	invalidate: () => void;
	toggleBridge: (next: boolean) => void;
	toggleTunnel: (next: boolean) => void;
	regenerate: () => void;
	confirmOpen: boolean;
	setConfirmOpen: (open: boolean) => void;
	confirmTunnel: () => void;
	tokenOpen: boolean;
	setTokenOpen: (open: boolean) => void;
	restartTunnel: () => void;
}

export function useMobileBridge(active: boolean): MobileBridge {
	const queryClient = useQueryClient();

	const query = useQuery({
		queryKey: mobileStatusQueryKey,
		queryFn: fetchMobileStatus,
		enabled: active,
		refetchInterval: (q) => tunnelRefetchInterval(q.state.data?.tunnel?.state),
	});

	const reportedOpen = useRef(false);
	const initialEnabled = query.data?.enabled;
	useEffect(() => {
		if (!active) {
			reportedOpen.current = false;
			return;
		}
		if (initialEnabled === undefined || reportedOpen.current) return;
		reportedOpen.current = true;
		void captureRendererEvent("opr.renderer.mobile_connect_opened", { bridge_enabled: initialEnabled });
	}, [active, initialEnabled]);

	const invalidate = () => {
		void queryClient.invalidateQueries({ queryKey: mobileStatusQueryKey });
	};

	const enable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/enable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const disable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/disable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const regenerateMutation = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/regenerate");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const tunnelEnable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/enable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const tunnelDisable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/disable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const status = query.data;
	const enabled = status?.enabled ?? false;
	const busy = enable.isPending || disable.isPending || regenerateMutation.isPending;

	const clearActionErrors = () => {
		enable.reset();
		disable.reset();
		regenerateMutation.reset();
		tunnelEnable.reset();
		tunnelDisable.reset();
	};

	const tunnel = status?.tunnel;
	const tunnelLive = tunnel?.state === "live" && tunnel.url !== "";
	const address = tunnelLive && tunnel ? tunnel.url : status ? `${status.host}:${status.port}` : undefined;
	const tunnelBusy = tunnelEnable.isPending || tunnelDisable.isPending;
	const tunnelOn = Boolean(
		tunnelLive || tunnel?.state === "starting" || tunnel?.state === "downloading" || tunnel?.state === "reconnecting",
	);
	const needsAuthtoken = tunnel?.needsAuthtoken ?? false;
	const [confirmOpen, setConfirmOpen] = useState(false);
	const [tokenOpen, setTokenOpen] = useState(false);
	const [seenNeedsAuthtoken, setSeenNeedsAuthtoken] = useState(false);
	if (needsAuthtoken !== seenNeedsAuthtoken) {
		setSeenNeedsAuthtoken(needsAuthtoken);
		if (needsAuthtoken) setTokenOpen(true);
	}

	const toggleTunnel = (next: boolean) => {
		if (tunnelBusy) return;
		clearActionErrors();
		if (!next) {
			tunnelDisable.mutate();
			return;
		}
		if (!tunnelAlreadyConfirmed()) {
			setConfirmOpen(true);
			return;
		}
		tunnelEnable.mutate();
	};

	const toggleBridge = (next: boolean) => {
		if (busy) return;
		clearActionErrors();
		const report = (outcome: "succeeded" | "failed") => {
			void captureRendererEvent("opr.renderer.mobile_bridge_toggled", { enabled: next, outcome });
		};
		const mutation = next ? enable : disable;
		mutation.mutate(undefined, { onSuccess: () => report("succeeded"), onError: () => report("failed") });
	};

	const regenerate = () => {
		clearActionErrors();
		regenerateMutation.mutate();
	};

	const confirmTunnel = () => {
		tunnelEnable.mutate();
	};

	const restartTunnel = () => {
		clearActionErrors();
		tunnelDisable.mutate(undefined, { onSuccess: () => tunnelEnable.mutate() });
	};

	const actionError =
		(enable.error instanceof Error && enable.error.message) ||
		(disable.error instanceof Error && disable.error.message) ||
		(regenerateMutation.error instanceof Error && regenerateMutation.error.message) ||
		(tunnelEnable.error instanceof Error && tunnelEnable.error.message) ||
		(tunnelDisable.error instanceof Error && tunnelDisable.error.message) ||
		null;

	return {
		query,
		status,
		enabled,
		busy,
		tunnel,
		tunnelLive: Boolean(tunnelLive),
		tunnelOn,
		tunnelBusy,
		address,
		actionError,
		invalidate,
		toggleBridge,
		toggleTunnel,
		regenerate,
		confirmOpen,
		setConfirmOpen,
		confirmTunnel,
		tokenOpen,
		setTokenOpen,
		restartTunnel,
	};
}
