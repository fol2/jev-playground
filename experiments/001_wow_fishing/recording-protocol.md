# Pilot recording and annotation protocol

Start with 3–5 manually played casts in one short recording. Keep the camera and
window geometry fixed, and include a few seconds before casting and after retrieval.
Keep the bobber visible at original resolution. Retain ordinary waiting, not just
successful bites. Audio is optional and unused in the first visual comparison.

Store the clip in `data/001_wow_fishing/`. Record the WoW variant/build if available,
scene, display, window mode, capture dimensions, frame rate/time base and whether
the clip has been cropped or resized. Preserve the original. Avoid capturing
unrelated private windows or chat where practical.

## Annotation fields

For each cast, record:

| Field | Meaning |
| --- | --- |
| recording_id / recording_sha256 | Stable source identity |
| cast_id | Unique cast within that recording |
| start_ms / end_ms | Cast interval relative to video start |
| initial_roi_xywh | Manually selected bobber rectangle in original frame pixels |
| visible_bite_onset_ms | First visible bite evidence; null when absent or uncertain |
| visible_bite_end_ms | Last visibly supported opportunity; null if unknown |
| manual_reel_ms | Human retrieval input if observable; separate from bite onset |
| tracking_intervals | Occlusion, loss, camera movement and geometry changes |
| target_boxes | Timestamped bobber rectangles for tracking checks |
| label_status / notes | Confirmed, ambiguous or unlabelled, with explanation |
| split | Development or held-out, assigned at session/cast level |

Use presentation timestamps for variable-frame-rate footage, not an assumed frame
rate. Never substitute the human click time for visible bite onset. Preserve
ambiguous cases explicitly; report their count and how evaluation handles them.
Annotations remain separate from model inputs.

After checking the pilot, collect the larger exploratory set with both ordinary
water motion and difficult/negative cases. Keep entire recording sessions together
where practical so neighbouring casts do not leak nearly identical scenery into
development and test sets.
