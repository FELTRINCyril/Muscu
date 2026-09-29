CREATE TABLE `body_measurements` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text,
	`metric` text NOT NULL,
	`value` real NOT NULL,
	`measured_at` integer NOT NULL,
	`source` text DEFAULT 'manual' NOT NULL,
	`health_uuid` text,
	`updated_at` integer DEFAULT 0 NOT NULL,
	`deleted` integer DEFAULT 0 NOT NULL,
	`dirty` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE INDEX `body_measurements_metric_at` ON `body_measurements` (`metric`,`measured_at`);