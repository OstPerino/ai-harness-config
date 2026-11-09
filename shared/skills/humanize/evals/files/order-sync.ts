import { api } from '@/api'
import { useOrdersStore } from '@/stores/orders'

const RETRY_DELAYS = [500, 1500, 4000]

let inflight: Promise<void> | null = null

export async function syncOrders(spotId: number, force = false): Promise<void> {
  if (inflight && !force) return inflight

  const store = useOrdersStore()

  inflight = (async () => {
    let lastError: unknown = null

    for (let attempt = 0; attempt <= RETRY_DELAYS.length; attempt++) {
      try {
        const { data } = await api.get(`/spots/${spotId}/orders`, {
          params: { updated_after: store.lastSyncedAt ?? undefined },
        })

        if (!data || !Array.isArray(data.items)) {
          store.lastSyncedAt = new Date().toISOString()
          return
        }

        store.merge(data.items)
        store.lastSyncedAt = data.synced_at ?? new Date().toISOString()
        return
      } catch (e) {
        lastError = e
        const delay = RETRY_DELAYS[attempt]
        if (delay === undefined) break
        await new Promise((r) => setTimeout(r, delay))
      }
    }

    store.syncError = true
    throw lastError
  })()

  try {
    await inflight
  } finally {
    inflight = null
  }
}
