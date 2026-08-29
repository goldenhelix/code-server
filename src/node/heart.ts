import { logger } from "@coder/logger"
import { promises as fs } from "fs"
import { Emitter } from "../common/emitter"
import { wrapper } from "./wrapper"

/**
 * Provides a heartbeat using a local file to indicate activity.
 */
export class Heart {
  private heartbeatTimer?: NodeJS.Timeout
  private idleCheckTimer?: NodeJS.Timeout
  private heartbeatInterval = 60000
  public lastHeartbeat = 0
  private readonly _onChange = new Emitter<"alive" | "expired" | "unknown">()
  readonly onChange = this._onChange.event
  private state: "alive" | "expired" | "unknown" = "expired"

  public constructor(
    private readonly heartbeatPath: string,
    private readonly idleTimeout: number | undefined,
    private readonly isActive: () => Promise<boolean>,
  ) {
    this.beat = this.beat.bind(this)
    this.alive = this.alive.bind(this)
    // Start idle check timer if timeout is configured
    if (this.idleTimeout) {
      this.startIdleCheck()
    }
  }

  private setState(state: typeof this.state) {
    if (this.state !== state) {
      this.state = state
      this._onChange.emit(this.state)
    }
  }

  public alive(): boolean {
    const now = Date.now()
    return now - this.lastHeartbeat < this.heartbeatInterval
  }
  /**
   * Write to the heartbeat file if we haven't already done so within the
   * timeout and start or reset a timer that keeps running as long as there is
   * activity. Failures are logged as warnings.
   */
  public async beat(): Promise<void> {
    if (this.alive()) {
      this.setState("alive")
      return
    }

    logger.debug("heartbeat")
    this.lastHeartbeat = Date.now()
    if (typeof this.heartbeatTimer !== "undefined") {
      clearTimeout(this.heartbeatTimer)
    }

    this.heartbeatTimer = setTimeout(async () => {
      try {
        if (await this.isActive()) {
          this.beat()
        } else {
          this.setState("expired")
        }
      } catch (error: unknown) {
        logger.warn((error as Error).message)
        this.setState("unknown")
      }
    }, this.heartbeatInterval)

    this.setState("alive")

    try {
      return await fs.writeFile(this.heartbeatPath, "")
    } catch (error: any) {
      logger.warn(error.message)
    }
  }

  private startIdleCheck(): void {
    // Check every minute if the idle timeout has been exceeded
    this.idleCheckTimer = setInterval(() => {
      const timeSinceLastBeat = Date.now() - this.lastHeartbeat
      if (timeSinceLastBeat > this.idleTimeout! * 60 * 1000) {
        logger.warn(`Idle timeout of ${this.idleTimeout} minutes exceeded`)
        wrapper.exit(5)
      }
    }, 60000)
  }

  /**
   * Call to clear any heartbeatTimer for shutdown.
   */
  public dispose(): void {
    if (typeof this.heartbeatTimer !== "undefined") {
      clearTimeout(this.heartbeatTimer)
    }
    if (typeof this.idleCheckTimer !== "undefined") {
      clearInterval(this.idleCheckTimer)
    }
  }
}
